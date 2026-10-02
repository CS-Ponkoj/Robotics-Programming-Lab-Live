param(
    [switch]$EnableAi,
    # Serve the slower Flutter debug build with hot reload instead of a release build.
    [switch]$DebugFrontend,
    [int]$FrontendPort = 8080,
    [int]$BackendPort = 5000,
    [int]$SandboxPort = 5001
)

$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$backendRoot = Join-Path $repositoryRoot "backend"
Import-Module (Join-Path $PSScriptRoot "local-environment.psm1") -Force
$privateConfigPath = Get-RoboticsPrivateConfigPath -RepositoryRoot $repositoryRoot
$python = Get-RoboticsPythonExecutable -RepositoryRoot $repositoryRoot -EnsureDependencies
$stateRoot = Get-RoboticsRuntimeRoot -RepositoryRoot $repositoryRoot
$stateFile = Join-Path $stateRoot "state.json"
$logRoot = Join-Path $stateRoot "logs"
$safeFrontendRoot = Join-Path $stateRoot "frontend"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter is not available on PATH. Install Flutter or open a terminal where 'flutter --version' works."
}
$requestedPorts = @($FrontendPort, $BackendPort, $SandboxPort)
$occupiedPorts = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -in $requestedPorts } |
    Select-Object -Unique LocalPort, OwningProcess)
if ($occupiedPorts.Count -gt 0) {
    $details = $occupiedPorts | ForEach-Object { "port $($_.LocalPort) (PID $($_.OwningProcess))" }
    throw "A requested local port is already in use: $($details -join ', '). Stop the older project process or select different port parameters."
}
if (Test-Path -LiteralPath $stateFile) {
    $existing = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    $running = @($existing.processes | Where-Object { Get-Process -Id $_.id -ErrorAction SilentlyContinue })
    if ($running.Count -gt 0) {
        throw "The local application is already running. Use .\scripts\stop-local.ps1 first."
    }
    Remove-Item -LiteralPath $stateFile -Force
}

New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
if (-not (Test-Path -LiteralPath $privateConfigPath)) {
    throw "Neon configuration is missing. Add NEON_DATABASE_URL to the repository root .env file."
}
$previousConfigPath = [Environment]::GetEnvironmentVariable("ROBOTICS_ENV_FILE", "Process")
[Environment]::SetEnvironmentVariable("ROBOTICS_ENV_FILE", $privateConfigPath, "Process")
try {
    Push-Location $backendRoot
    try {
        $databaseUrl = (& $python -c "from config import get_settings; print(get_settings().cloud_database_url or '')" 2>$null | Select-Object -Last 1)
        $aiAvailable = ((& $python -c "from config import get_settings; print('true' if get_settings().openai_api_key else 'false')" 2>$null | Select-Object -Last 1) -eq "true")
    } finally {
        Pop-Location
    }
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($databaseUrl)) {
        throw "NEON_DATABASE_URL is missing or invalid in the repository root .env file."
    }
    $databaseUrl = $databaseUrl.Trim()
    if (-not $databaseUrl.Contains(".neon.tech")) {
        throw "The local launcher supports the configured Neon database only."
    }
} finally {
    [Environment]::SetEnvironmentVariable("ROBOTICS_ENV_FILE", $previousConfigPath, "Process")
}
Write-Output "Using the configured Neon staging database."
if ($EnableAi -and -not $aiAvailable) {
    throw "-EnableAi was requested, but OPENAI_API_KEY is not configured in the repository root .env file."
}

function New-LocalToken {
    $bytes = New-Object byte[] 32
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
    } finally {
        $generator.Dispose()
    }
    return ([BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
}

function Start-ProjectProcess {
    param(
        [string]$Name,
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory,
        [hashtable]$Environment = @{}
    )

    $previous = @{}
    foreach ($key in $Environment.Keys) {
        $previous[$key] = [System.Environment]::GetEnvironmentVariable($key, "Process")
        [System.Environment]::SetEnvironmentVariable($key, [string]$Environment[$key], "Process")
    }
    try {
        $stdout = Join-Path $logRoot "$Name.stdout.log"
        $stderr = Join-Path $logRoot "$Name.stderr.log"
        foreach ($logFile in @($stdout, $stderr)) {
            if (Test-Path -LiteralPath $logFile) {
                Remove-Item -LiteralPath $logFile -Force
            }
        }
        return Start-Process -FilePath $FilePath -ArgumentList $ArgumentList `
            -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    } finally {
        foreach ($key in $Environment.Keys) {
            [System.Environment]::SetEnvironmentVariable($key, $previous[$key], "Process")
        }
    }
}

function Stop-ProjectProcessTree {
    param([int]$ProcessId)
    if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
        & taskkill.exe /PID $ProcessId /T /F 2>$null | Out-Null
    }
}

function Wait-ForEndpoint {
    param(
        [string]$Name,
        [string]$Url,
        [int]$Attempts = 60,
        [switch]$AcceptAnySuccess
    )
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            if ($AcceptAnySuccess) {
                $response = Invoke-WebRequest -Uri $Url -TimeoutSec 2 -UseBasicParsing
                if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) { return }
            } else {
                $response = Invoke-RestMethod -Uri $Url -TimeoutSec 2
                if ($response.status -eq "ok") { return }
            }
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }
    throw "$Name did not become healthy at $Url. Review $logRoot."
}

function Wait-ForLogMessage {
    param(
        [string]$Name,
        [string]$Path,
        [string]$Text,
        [int]$ProcessId,
        [int]$Attempts = 240
    )
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        if (Test-Path -LiteralPath $Path) {
            $content = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
            if ($content -and $content.Contains($Text)) { return }
        }
        if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
            throw "$Name exited before it became ready. Review $logRoot."
        }
        Start-Sleep -Milliseconds 500
    }
    throw "$Name did not become ready. Review $logRoot."
}

$token = New-LocalToken
$processes = @()
try {
    $previousDatabaseUrl = [System.Environment]::GetEnvironmentVariable("DATABASE_URL", "Process")
    [System.Environment]::SetEnvironmentVariable("DATABASE_URL", $databaseUrl, "Process")
    Push-Location $backendRoot
    try {
        & $python -m alembic upgrade head
        if ($LASTEXITCODE -ne 0) { throw "Database migration failed." }
    } finally {
        Pop-Location
        [System.Environment]::SetEnvironmentVariable("DATABASE_URL", $previousDatabaseUrl, "Process")
    }

    $sandbox = Start-ProjectProcess -Name "sandbox" -FilePath $python `
        -ArgumentList @("-m", "uvicorn", "sandbox_service:app", "--host", "127.0.0.1", "--port", "$SandboxPort", "--no-server-header") `
        -WorkingDirectory $backendRoot -Environment @{
            SANDBOX_API_TOKEN = $token
            SANDBOX_MAX_CONCURRENT_EXECUTIONS = "2"
        }
    $processes += [pscustomobject]@{ name = "sandbox"; id = $sandbox.Id }
    Wait-ForEndpoint -Name "Sandbox" -Url "http://127.0.0.1:$SandboxPort/health"

    $backendEnvironment = @{
        ENVIRONMENT = "development"
        DATABASE_URL = $databaseUrl
        AUTO_CREATE_SCHEMA = "false"
        PUBLIC_APP_URL = "http://127.0.0.1:$FrontendPort"
        ALLOWED_ORIGINS = "http://127.0.0.1:$FrontendPort,http://localhost:$FrontendPort"
        SANDBOX_BACKEND = "remote"
        SANDBOX_URL = "http://127.0.0.1:$SandboxPort"
        SANDBOX_API_TOKEN = $token
        ROBOTICS_ENV_FILE = $privateConfigPath
    }
    $backend = Start-ProjectProcess -Name "backend" -FilePath $python `
        -ArgumentList @("-m", "uvicorn", "app:app", "--host", "127.0.0.1", "--port", "$BackendPort", "--no-server-header") `
        -WorkingDirectory $backendRoot -Environment $backendEnvironment
    $processes += [pscustomobject]@{ name = "backend"; id = $backend.Id }
    Wait-ForEndpoint -Name "Backend" -Url "http://127.0.0.1:$BackendPort/health"

    $resolvedSafeRoot = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "RoboticsProgrammingLab"))
    $resolvedFrontend = [System.IO.Path]::GetFullPath($safeFrontendRoot)
    if (-not $resolvedFrontend.StartsWith($resolvedSafeRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to prepare a Flutter copy outside the expected LOCALAPPDATA folder."
    }
    if (Test-Path -LiteralPath $resolvedFrontend) {
        Remove-Item -LiteralPath $resolvedFrontend -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $resolvedFrontend | Out-Null
    foreach ($directory in @("fonts", "lib", "web")) {
        Copy-Item -LiteralPath (Join-Path $repositoryRoot "frontend\$directory") -Destination $resolvedFrontend -Recurse
    }
    foreach ($file in @(".metadata", "analysis_options.yaml", "pubspec.lock", "pubspec.yaml")) {
        Copy-Item -LiteralPath (Join-Path $repositoryRoot "frontend\$file") -Destination $resolvedFrontend
    }
    Push-Location $resolvedFrontend
    try {
        & flutter pub get
        if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed." }
    } finally {
        Pop-Location
    }
    $apiDefine = "--dart-define=API_BASE_URL=http://127.0.0.1:$BackendPort"
    if ($DebugFrontend) {
        $flutterCommand = (Get-Command flutter).Source
        $frontend = Start-ProjectProcess -Name "frontend" -FilePath $flutterCommand `
            -ArgumentList @("run", "-d", "web-server", "--web-hostname", "127.0.0.1", "--web-port", "$FrontendPort", $apiDefine) `
            -WorkingDirectory $resolvedFrontend
        $processes += [pscustomobject]@{ name = "frontend"; id = $frontend.Id }
        Wait-ForLogMessage -Name "Frontend compiler" `
            -Path (Join-Path $logRoot "frontend.stdout.log") `
            -Text "is being served at http://127.0.0.1:$FrontendPort" `
            -ProcessId $frontend.Id
        Wait-ForEndpoint -Name "Frontend shell" -Url "http://127.0.0.1:$FrontendPort" -Attempts 240 -AcceptAnySuccess
        # Flutter's web server can return index.html before the generated Dart
        # entrypoint is available. Wait for that module so the first browser load
        # cannot race the compiler and render a blank page.
        Wait-ForEndpoint -Name "Frontend entrypoint" -Url "http://127.0.0.1:$FrontendPort/web_entrypoint.dart" -Attempts 240 -AcceptAnySuccess
    } else {
        # The same optimized build that Vercel deploys: one compiled bundle
        # instead of hundreds of debug modules.
        Write-Output "Building the Flutter web release bundle..."
        # An explicit output path ignores any machine-wide Flutter build-dir setting.
        $webBuild = Join-Path $resolvedFrontend "build\web"
        Push-Location $resolvedFrontend
        try {
            & flutter build web --release $apiDefine --output $webBuild
            if ($LASTEXITCODE -ne 0) { throw "flutter build web failed." }
        } finally {
            Pop-Location
        }
        # Start-Process joins arguments without quoting; the checkout path has spaces.
        $serverScript = '"' + (Join-Path $PSScriptRoot "serve_web.py") + '"'
        $webRoot = '"' + $webBuild + '"'
        $frontend = Start-ProjectProcess -Name "frontend" -FilePath $python `
            -ArgumentList @($serverScript, "--directory", $webRoot, "--port", "$FrontendPort") `
            -WorkingDirectory $resolvedFrontend
        $processes += [pscustomobject]@{ name = "frontend"; id = $frontend.Id }
        Wait-ForEndpoint -Name "Frontend" -Url "http://127.0.0.1:$FrontendPort/main.dart.js" -AcceptAnySuccess
    }

    [pscustomobject]@{
        repository = $repositoryRoot
        startedAt = (Get-Date).ToString("o")
        processes = $processes
        frontendUrl = "http://127.0.0.1:$FrontendPort"
        backendUrl = "http://127.0.0.1:$BackendPort"
        sandboxUrl = "http://127.0.0.1:$SandboxPort"
        databaseBackend = "postgresql"
        databaseProvider = "neon"
        aiAvailable = [bool]$aiAvailable
        aiEnabledByDefault = $false
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $stateFile -Encoding UTF8

    Write-Output "Robotics Programming Lab is ready."
    Write-Output "Frontend: http://127.0.0.1:$FrontendPort"
    Write-Output "Backend:  http://127.0.0.1:$BackendPort/health"
    Write-Output "Sandbox:  http://127.0.0.1:$SandboxPort/health"
    Write-Output "Database: Neon staging PostgreSQL"
    Write-Output "AI available: $([bool]$aiAvailable); off until the assignment switch is turned on."
    Write-Output "Stop with: .\scripts\stop-local.ps1"
} catch {
    foreach ($process in $processes) {
        Stop-ProjectProcessTree -ProcessId $process.id
    }
    throw
}
