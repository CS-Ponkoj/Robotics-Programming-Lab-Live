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
    throw "Docker Desktop is required for local PostgreSQL. Install Docker Desktop, reopen PowerShell, and run setup again."
}

Write-Output "Local Python setup is ready."
Write-Output "Python: $python"
& $python --version
Write-Output "Docker command is available. Start Docker Desktop before running the application."
Write-Output "Start the application with: .\scripts\run-local.ps1 -FrontendPort 8180 -BackendPort 5100 -SandboxPort 5101"
