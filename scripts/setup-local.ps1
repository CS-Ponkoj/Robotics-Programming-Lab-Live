param([switch]$Repair)

$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
Import-Module (Join-Path $PSScriptRoot "local-environment.psm1") -Force

$stateFile = Join-Path (Get-RoboticsRuntimeRoot -RepositoryRoot $repositoryRoot) "state.json"
if (Test-Path -LiteralPath $stateFile) {
    $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    $running = @($state.processes | Where-Object {
        Get-Process -Id $_.id -ErrorAction SilentlyContinue
    })
    if ($running.Count -gt 0) {
        throw "Stop the local application before setup: .\scripts\stop-local.ps1"
    }
}

$python = Get-RoboticsPythonExecutable -RepositoryRoot $repositoryRoot `
    -EnsureDependencies -RefreshDependencies:$Repair

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker Desktop is required for the sandbox and ROS 2 graders. Install Docker Desktop, reopen PowerShell, and run setup again."
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter is required for the web interface. Install Flutter, add it to PATH, reopen PowerShell, and run setup again."
}
& docker compose version | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Docker Compose is unavailable. Update Docker Desktop and run setup again."
}
& flutter --version | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Flutter is present but could not run. Complete 'flutter doctor' repairs and run setup again."
}

Write-Output "Local Python setup is ready."
Write-Output "Python: $python"
& $python --version
Write-Output "Private config: $(Get-RoboticsPrivateConfigPath -RepositoryRoot $repositoryRoot)"
Write-Output "Database: Neon PostgreSQL (configured in the private .env file)"
Write-Output "Docker and Flutter commands are available. Start Docker Desktop before running ROS assignments."
Write-Output "Start the application with: .\scripts\run-local.ps1"
Write-Output "Then open: http://127.0.0.1:8180/app"
