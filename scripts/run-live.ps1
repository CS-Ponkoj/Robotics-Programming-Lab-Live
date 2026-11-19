param(
    [int]$FrontendPort = 8180,
    [int]$BackendPort = 5100,
    [string]$ApiBaseUrl = "https://rpl.ponkoj.com/api",
    [switch]$SkipBuild,
    # Restart a running stack without rebuilding (backend-only deploys).
    [switch]$Restart
)

# Starts the self-hosted production stack on the lab PC: database migrations,
# the API (Docker-isolated code execution), the Flutter web build, and Caddy,
# which serves both on 127.0.0.1:8080 with the API under /api. Settings come
# from the ignored repository-root .env. Cloudflare Tunnel publishes port 8080;
# nothing here listens beyond 127.0.0.1.

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "local-environment.psm1") -Force

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$backendRoot = Join-Path $repositoryRoot "backend"
$python = Get-RoboticsPythonExecutable -RepositoryRoot $repositoryRoot
$runtime = Join-Path $env:LOCALAPPDATA "RoboticsProgrammingLab\runtime\RPL-Live"
$webBuild = Join-Path $runtime "web"
$logs = Join-Path $runtime "logs"
New-Item -ItemType Directory -Force $logs | Out-Null

if (-not (Select-String -Path (Join-Path $repositoryRoot ".env") -Pattern '^ENVIRONMENT=production$' -Quiet)) {
    throw "The live launcher requires ENVIRONMENT=production in the repository-root .env."
}

# One launch at a time. The scheduled task runs this script every five
# minutes with -SkipBuild as a watchdog; while a deploy is building or
# restarting, the watchdog must not start a second copy of the stack.
$watchdog = $SkipBuild -and -not $Restart
$launchLock = [System.Threading.Mutex]::new($false, "Global\RoboticsProgrammingLab-RPL-Live-Launch")
$haveLock = $false
try {
    $haveLock = $launchLock.WaitOne($(if ($watchdog) { 0 } else { [TimeSpan]::FromMinutes(15) }))
} catch [System.Threading.AbandonedMutexException] {
    # A previous launch ended without releasing the lock; it is ours now.
    $haveLock = $true
}
if (-not $haveLock) {
    if ($watchdog) {
        Write-Output "Another live launch is in progress; this run changes nothing."
        exit 0
    }
    throw "Another live launch did not finish within 15 minutes."
}
trap {
    if ($haveLock) { $launchLock.ReleaseMutex(); $haveLock = $false }
    break
}

$components = @('uvicorn app:app', 'serve_web\.py', 'Caddyfile\.live', 'tunnel run rpl-live')
$commandLines = @(Get-CimInstance Win32_Process | ForEach-Object { $_.CommandLine } | Where-Object { $_ })
$runningComponents = @($components | Where-Object { $pattern = $_; $commandLines -match $pattern })
if ($watchdog -and $runningComponents.Count -eq $components.Count) {
    # Already running, so a repeated scheduled run changes nothing.
    $launchLock.ReleaseMutex()
    exit 0
}
# A deploy builds first while the old stack keeps serving, then replaces it
# just before starting (see below). A partly running stack (for example after
# a killed start) is replaced the same way.
$replaceRunning = $runningComponents.Count -gt 0

# After a reboot Docker Desktop can take several minutes to accept commands.
for ($i = 0; $i -lt 60; $i++) {
    Invoke-RoboticsNative docker info | Out-Null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 5
}
if ($LASTEXITCODE -ne 0) { throw "Docker did not become ready." }

Invoke-RoboticsNative docker start rpl-live-postgres | Out-Null
for ($i = 0; $i -lt 30; $i++) {
    Invoke-RoboticsNative docker exec rpl-live-postgres pg_isready -q -U rpl -d rpl_live
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 1
}
if ($LASTEXITCODE -ne 0) { throw "PostgreSQL did not become ready." }

Push-Location $backendRoot
try {
    Invoke-RoboticsNative $python -m alembic -c alembic.ini upgrade head
    if ($LASTEXITCODE -ne 0) { throw "Database migration failed." }
} finally {
    Pop-Location
}

if (-not $SkipBuild) {
    Push-Location (Join-Path $repositoryRoot "frontend")
    try {
        # No offline cache: the default offline-first service worker kept
        # browsers on an old build after each deploy.
        Invoke-RoboticsNative flutter build web --release --pwa-strategy=none "--dart-define=API_BASE_URL=$ApiBaseUrl" --output $webBuild
        if ($LASTEXITCODE -ne 0) { throw "flutter build web failed." }
    } finally {
        Pop-Location
    }
}

if ($replaceRunning) {
    & (Join-Path $PSScriptRoot "stop-live.ps1") | Out-Null
}

$release = (git -C $repositoryRoot rev-parse HEAD).Trim()
$env:RENDER_GIT_COMMIT = $release

# Managed secrets (set with scripts/set-live-secret.ps1) are encrypted for this
# Windows user. They are given to the API process only, then removed from this
# shell so the web server, Caddy, and the tunnel never inherit them.
$secretNames = @(Get-RoboticsLiveSecretNames)
$aiKey = "not configured"
foreach ($name in $secretNames) {
    Set-Item -Path "Env:$name" -Value (Read-RoboticsLiveSecret -Name $name)
    if ($name -eq "OPENAI_API_KEY") { $aiKey = "configured (managed secret)" }
}
try {
    Start-Process -FilePath $python -WindowStyle Hidden -WorkingDirectory $backendRoot `
        -ArgumentList @("-m", "uvicorn", "app:app", "--host", "127.0.0.1", "--port", "$BackendPort", "--proxy-headers", "--root-path", "/api", "--no-server-header") `
        -RedirectStandardOutput (Join-Path $logs "api.out.log") -RedirectStandardError (Join-Path $logs "api.err.log")
} finally {
    foreach ($name in $secretNames) { Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue }
}

Start-Process -FilePath $python -WindowStyle Hidden `
    -ArgumentList @("`"$(Join-Path $PSScriptRoot 'serve_web.py')`"", "--directory", "`"$webBuild`"", "--port", "$FrontendPort") `
    -RedirectStandardOutput (Join-Path $logs "web.out.log") -RedirectStandardError (Join-Path $logs "web.err.log")

$caddy = (Get-Command caddy -ErrorAction Stop).Source
Start-Process -FilePath $caddy -WindowStyle Hidden `
    -ArgumentList @("run", "--config", "`"$(Join-Path $PSScriptRoot 'Caddyfile.live')`"", "--adapter", "caddyfile") `
    -RedirectStandardOutput (Join-Path $logs "caddy.out.log") -RedirectStandardError (Join-Path $logs "caddy.err.log")

$cloudflared = (Get-Command cloudflared -ErrorAction Stop).Source
Start-Process -FilePath $cloudflared -WindowStyle Hidden `
    -ArgumentList @("tunnel", "run", "rpl-live") `
    -RedirectStandardOutput (Join-Path $logs "tunnel.out.log") -RedirectStandardError (Join-Path $logs "tunnel.err.log")

Write-Output "Live stack starting at release $($release.Substring(0, 12))."
Write-Output "AI tutor key: $aiKey. The course switch is in Instructor Studio."
Write-Output "Local address: http://127.0.0.1:8080/app (API at /api)"
Write-Output "Logs: $logs"
$launchLock.ReleaseMutex()
$haveLock = $false
