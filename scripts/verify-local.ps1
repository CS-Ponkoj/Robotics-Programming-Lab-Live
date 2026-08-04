param(
    [string]$ApiBaseUrl = "http://127.0.0.1:5000"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$python = Join-Path $repositoryRoot "venv\Scripts\python.exe"

if (-not (Test-Path -LiteralPath $python)) {
    throw "Python environment not found at $python."
}

Push-Location (Join-Path $repositoryRoot "backend")
try {
    & $python -m pytest tests -q
    if ($LASTEXITCODE -ne 0) { throw "Backend tests failed." }
    & $python -m pip check
    if ($LASTEXITCODE -ne 0) { throw "Python dependency validation failed." }
    & $python -m compileall -q .
    if ($LASTEXITCODE -ne 0) { throw "Python compilation validation failed." }
} finally {
    Pop-Location
}

& (Join-Path $PSScriptRoot "verify_frontend_onedrive.ps1") -ApiBaseUrl $ApiBaseUrl
if ($LASTEXITCODE -ne 0) { throw "Flutter verification failed." }

Push-Location $repositoryRoot
try {
    git diff --check
    if ($LASTEXITCODE -ne 0) { throw "Git whitespace validation failed." }
} finally {
    Pop-Location
}

$stateFile = Join-Path $repositoryRoot ".local-run\state.json"
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
