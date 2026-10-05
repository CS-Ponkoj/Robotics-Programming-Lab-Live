param(
    [string]$ApiBaseUrl = "http://127.0.0.1:5100"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
Import-Module (Join-Path $PSScriptRoot "local-environment.psm1") -Force
$python = Get-RoboticsPythonExecutable -RepositoryRoot $repositoryRoot -EnsureDependencies

& (Join-Path $PSScriptRoot "verify-local-layout.ps1")
if (-not $?) { throw "Portable local layout validation failed." }
& (Join-Path $PSScriptRoot "verify-private-config.ps1")
if (-not $?) { throw "Private Neon configuration validation failed." }

& (Join-Path $PSScriptRoot "clean-local.ps1")
if (-not $?) { throw "Safe local cleanup dry-run validation failed." }

Push-Location (Join-Path $repositoryRoot "backend")
try {
    & $python -m pytest -p no:cacheprovider tests -q
    if ($LASTEXITCODE -ne 0) { throw "Backend tests failed." }
    & $python -m pip check
    if ($LASTEXITCODE -ne 0) { throw "Python dependency validation failed." }
    & $python -m compileall -q .
    if ($LASTEXITCODE -ne 0) { throw "Python compilation validation failed." }
} finally {
    Pop-Location
}

& (Join-Path $PSScriptRoot "verify_frontend_onedrive.ps1") -ApiBaseUrl $ApiBaseUrl
if (-not $?) { throw "Flutter verification failed." }

Push-Location $repositoryRoot
try {
    & (Join-Path $PSScriptRoot "check-release.ps1") -AllowDirty -SkipRemoteCheck
    if (-not $?) { throw "Fresh-clone source validation failed." }
    git diff --check
    if ($LASTEXITCODE -ne 0) { throw "Git whitespace validation failed." }
} finally {
    Pop-Location
}

$stateFile = Join-Path (Get-RoboticsRuntimeRoot -RepositoryRoot $repositoryRoot) "state.json"
if (Test-Path -LiteralPath $stateFile) {
    $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    $backendHealth = Invoke-RestMethod -Uri "$($state.backendUrl)/health" -TimeoutSec 5
    $sandboxHealth = Invoke-RestMethod -Uri "$($state.sandboxUrl)/health" -TimeoutSec 5
    if ($backendHealth.status -ne "ok" -or $sandboxHealth.status -ne "ok") {
        throw "A managed local service failed its health check."
    }
    Write-Output "Managed backend and sandbox health checks passed."
}

Write-Output "Complete local SQA verification passed."
