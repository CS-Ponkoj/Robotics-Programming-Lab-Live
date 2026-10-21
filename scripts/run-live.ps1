param(
    [int]$FrontendPort = 8180,
    [int]$BackendPort = 5100,
    [string]$ApiBaseUrl = "https://rpl-api.ponkoj.com",
    [switch]$SkipBuild
)

# Starts the self-hosted production stack on the lab PC: database migrations,
# the API (Docker-isolated code execution), and the Flutter web build. Settings
# come from the ignored repository-root .env. Cloudflare Tunnel publishes the
# two local ports; nothing here listens beyond 127.0.0.1.

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
        Invoke-RoboticsNative flutter build web --release "--dart-define=API_BASE_URL=$ApiBaseUrl" --output $webBuild
        if ($LASTEXITCODE -ne 0) { throw "flutter build web failed." }
    } finally {
        Pop-Location
    }
}

$release = (git -C $repositoryRoot rev-parse HEAD).Trim()
$env:RENDER_GIT_COMMIT = $release

Start-Process -FilePath $python -WindowStyle Hidden -WorkingDirectory $backendRoot `
    -ArgumentList @("-m", "uvicorn", "app:app", "--host", "127.0.0.1", "--port", "$BackendPort", "--proxy-headers", "--no-server-header") `
    -RedirectStandardOutput (Join-Path $logs "api.out.log") -RedirectStandardError (Join-Path $logs "api.err.log")

Start-Process -FilePath $python -WindowStyle Hidden `
    -ArgumentList @("`"$(Join-Path $PSScriptRoot 'serve_web.py')`"", "--directory", "`"$webBuild`"", "--port", "$FrontendPort") `
    -RedirectStandardOutput (Join-Path $logs "web.out.log") -RedirectStandardError (Join-Path $logs "web.err.log")

Write-Output "Live stack starting at release $($release.Substring(0, 12))."
Write-Output "API: http://127.0.0.1:$BackendPort  Web: http://127.0.0.1:$FrontendPort/app"
Write-Output "Logs: $logs"
