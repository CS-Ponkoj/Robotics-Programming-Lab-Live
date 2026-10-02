param(
    [string]$FrontendUrl = "",
    [string]$InstructorLogin = "",
    [switch]$Headed
)

# Run the end-to-end browser checks against the stack started by run-local.ps1.
# Playwright lives in its own environment so the application's pinned Python
# environment is unchanged. Tests use the installed Google Chrome.

$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
Import-Module (Join-Path $PSScriptRoot "local-environment.psm1") -Force
$python = Get-RoboticsPythonExecutable -RepositoryRoot $repositoryRoot

if (-not $FrontendUrl) {
    $stateFile = Join-Path (Get-RoboticsRuntimeRoot -RepositoryRoot $repositoryRoot) "state.json"
    if (-not (Test-Path -LiteralPath $stateFile)) {
        throw "The local application is not running. Start it with .\scripts\run-local.ps1 first."
    }
    $FrontendUrl = (Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json).frontendUrl
}

$environmentRoot = Join-Path (Split-Path (Get-RoboticsEnvironmentRoot -RepositoryRoot $repositoryRoot)) "browser-tests-venv"
$testPython = Join-Path $environmentRoot "Scripts\python.exe"
if (-not (Test-Path -LiteralPath $testPython)) {
    & $python -m venv $environmentRoot
    if ($LASTEXITCODE -ne 0) { throw "Could not create the browser-test environment." }
}
& $testPython -m pip install --quiet --disable-pip-version-check -r (Join-Path $PSScriptRoot "requirements-browser-tests.txt")
if ($LASTEXITCODE -ne 0) { throw "Could not install the browser-test requirements." }

$previous = @{}
$variables = @{ E2E_FRONTEND_URL = $FrontendUrl; E2E_HEADED = $(if ($Headed) { "1" } else { "" }) }
if ($InstructorLogin) {
    if (-not $env:E2E_INSTRUCTOR_PASSWORD) {
        $secure = Read-Host -AsSecureString "Password for instructor test account '$InstructorLogin'"
        $variables.E2E_INSTRUCTOR_PASSWORD = [System.Net.NetworkCredential]::new("", $secure).Password
    }
    $variables.E2E_INSTRUCTOR_LOGIN = $InstructorLogin
}
foreach ($key in $variables.Keys) {
    $previous[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
    [Environment]::SetEnvironmentVariable($key, $variables[$key], "Process")
}
try {
    & $testPython -m pytest -p no:cacheprovider (Join-Path $PSScriptRoot "browser_tests") -v
    if ($LASTEXITCODE -ne 0) { throw "Browser tests failed." }
} finally {
    foreach ($key in $variables.Keys) {
        [Environment]::SetEnvironmentVariable($key, $previous[$key], "Process")
    }
}
