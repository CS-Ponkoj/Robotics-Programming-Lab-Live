param(
    [string]$DatabaseUrl = "",
    [switch]$UseSqlite,
    [switch]$EnableAi,
    [int]$FrontendPort = 8080,
    [int]$BackendPort = 5000,
    [int]$SandboxPort = 5001,
    [int]$DatabasePort = 5432,
    [ValidateRange(1, 1440)][int]$BackupIntervalMinutes = 10
)

$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$backendRoot = Join-Path $repositoryRoot "backend"
Import-Module (Join-Path $PSScriptRoot "local-environment.psm1") -Force
$privateConfigPath = Get-RoboticsHandoffPrivateConfigPath -RepositoryRoot $repositoryRoot
$handoffDatabaseRoot = Get-RoboticsHandoffDatabaseRoot -RepositoryRoot $repositoryRoot
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
$localDatabaseSession = $null

if ($UseSqlite -and -not [string]::IsNullOrWhiteSpace($DatabaseUrl)) {
    throw "Use either -UseSqlite or -DatabaseUrl, not both."
}
if ($UseSqlite) {
    $DatabaseUrl = "sqlite:///robotics_lab_staging.db"
} elseif ([string]::IsNullOrWhiteSpace($DatabaseUrl)) {
    Import-Module (Join-Path $PSScriptRoot "local-database.psm1") -Force
    $localDatabaseSession = Start-RoboticsLocalPostgres `
        -RepositoryRoot $repositoryRoot `
        -DatabasePort $DatabasePort
    $DatabaseUrl = $localDatabaseSession.DatabaseUrl
    if ($localDatabaseSession.RestoredBackup) {
        Write-Output "Restored the newest verified PostgreSQL handoff backup."
    }
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
    [System.Environment]::SetEnvironmentVariable("DATABASE_URL", $DatabaseUrl, "Process")
    Push-Location $backendRoot
    try {
        & $python -m alembic upgrade head
        if ($LASTEXITCODE -ne 0) { throw "Database migration failed." }
        if ($localDatabaseSession -and -not $localDatabaseSession.HasSynchronizedBackup) {
            $sqliteSource = Join-Path $backendRoot "robotics_lab_staging.db"
            if (Test-Path -LiteralPath $sqliteSource) {
                $importReport = Join-Path $localDatabaseSession.RuntimeRoot "sqlite-import-report.json"
                & $python database_transfer.py `
                    --sqlite $sqliteSource `
                    --target-url $DatabaseUrl `
                    --report $importReport `
                    --if-empty
                if ($LASTEXITCODE -ne 0) {
                    throw "Existing SQLite data could not be transferred to local PostgreSQL."
                }
            }
        }
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
        DATABASE_URL = $DatabaseUrl
        AUTO_CREATE_SCHEMA = if ($DatabaseUrl.StartsWith("sqlite")) { "true" } else { "false" }
        PUBLIC_APP_URL = "http://127.0.0.1:$FrontendPort"
        ALLOWED_ORIGINS = "http://127.0.0.1:$FrontendPort,http://localhost:$FrontendPort"
        SANDBOX_BACKEND = "remote"
        SANDBOX_URL = "http://127.0.0.1:$SandboxPort"
        SANDBOX_API_TOKEN = $token
        OPENAI_API_KEY = ""
        ROBOTICS_ENV_FILE = $privateConfigPath
    }
    if ($EnableAi) {
        $backendEnvironment.Remove("OPENAI_API_KEY")
    }
    $backend = Start-ProjectProcess -Name "backend" -FilePath $python `
        -ArgumentList @("-m", "uvicorn", "app:app", "--host", "127.0.0.1", "--port", "$BackendPort", "--no-server-header") `
        -WorkingDirectory $backendRoot -Environment $backendEnvironment
    $processes += [pscustomobject]@{ name = "backend"; id = $backend.Id }
    Wait-ForEndpoint -Name "Backend" -Url "http://127.0.0.1:$BackendPort/health"

    if ($localDatabaseSession) {
        $powerShell = (Get-Process -Id $PID).Path
        $backupScript = Join-Path $PSScriptRoot "backup-local-database.ps1"
        $backupWorker = Start-ProjectProcess -Name "database-backup" -FilePath $powerShell `
            -ArgumentList @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$backupScript`"",
                "-SessionId", $localDatabaseSession.SessionId,
                "-DatabasePort", "$($localDatabaseSession.DatabasePort)",
                "-ProjectName", $localDatabaseSession.ProjectName,
                "-BackupRoot", "`"$($localDatabaseSession.BackupRoot)`"",
                "-RuntimeRoot", "`"$($localDatabaseSession.RuntimeRoot)`"",
                "-IntervalMinutes", "$BackupIntervalMinutes"
            ) `
            -WorkingDirectory $repositoryRoot
        $processes += [pscustomobject]@{ name = "database-backup"; id = $backupWorker.Id }
    }

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
    $flutterCommand = (Get-Command flutter).Source
    $frontend = Start-ProjectProcess -Name "frontend" -FilePath $flutterCommand `
        -ArgumentList @("run", "-d", "web-server", "--web-hostname", "127.0.0.1", "--web-port", "$FrontendPort", "--dart-define=API_BASE_URL=http://127.0.0.1:$BackendPort") `
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

    [pscustomobject]@{
        repository = $repositoryRoot
        startedAt = (Get-Date).ToString("o")
        processes = $processes
        frontendUrl = "http://127.0.0.1:$FrontendPort"
        backendUrl = "http://127.0.0.1:$BackendPort"
        sandboxUrl = "http://127.0.0.1:$SandboxPort"
        databaseBackend = if ($DatabaseUrl.StartsWith("sqlite")) { "sqlite" } else { "postgresql" }
        managedLocalDatabase = [bool]$localDatabaseSession
        localDatabaseSessionId = if ($localDatabaseSession) { $localDatabaseSession.SessionId } else { $null }
        localDatabaseProjectName = if ($localDatabaseSession) { $localDatabaseSession.ProjectName } else { $null }
        localDatabasePort = if ($localDatabaseSession) { $localDatabaseSession.DatabasePort } else { $null }
        localDatabaseBackupRoot = if ($localDatabaseSession) { $localDatabaseSession.BackupRoot } else { $null }
        localDatabaseRuntimeRoot = if ($localDatabaseSession) { $localDatabaseSession.RuntimeRoot } else { $null }
        aiEnabled = [bool]$EnableAi
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $stateFile -Encoding UTF8

    $databaseDescription = if (-not $localDatabaseSession) {
        if ($DatabaseUrl.StartsWith("sqlite")) { "SQLite fallback" } else { "externally configured" }
    } elseif ($localDatabaseSession.BackupRoot.Equals(
        $handoffDatabaseRoot,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        "local PostgreSQL with the unified local handoff package"
    } else {
        "local PostgreSQL with verified handoff backups"
    }

    Write-Output "Robotics Programming Lab is ready."
    Write-Output "Frontend: http://127.0.0.1:$FrontendPort"
    Write-Output "Backend:  http://127.0.0.1:$BackendPort/health"
    Write-Output "Sandbox:  http://127.0.0.1:$SandboxPort/health"
    Write-Output "Database: $databaseDescription"
    Write-Output "AI enabled: $([bool]$EnableAi)"
    if ($localDatabaseSession) {
        Write-Output "Automatic database backup: every $BackupIntervalMinutes minute(s) while the local stack is running"
    }
    Write-Output "Stop with: .\scripts\stop-local.ps1"
} catch {
    foreach ($process in $processes) {
        Stop-ProjectProcessTree -ProcessId $process.id
    }
    if ($localDatabaseSession) {
        try {
            Complete-RoboticsLocalPostgres `
                -RepositoryRoot $repositoryRoot `
                -SessionId $localDatabaseSession.SessionId `
                -DatabasePort $localDatabaseSession.DatabasePort `
                -ProjectName $localDatabaseSession.ProjectName `
                -BackupRoot $localDatabaseSession.BackupRoot `
                -RuntimeRoot $localDatabaseSession.RuntimeRoot | Out-Host
        } catch {
            Write-Warning "Local PostgreSQL recovery backup failed after startup error: $_"
        }
    }
    throw
}
