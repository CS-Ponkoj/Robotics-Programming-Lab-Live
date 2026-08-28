$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
Import-Module (Join-Path $PSScriptRoot "local-environment.psm1") -Force

$environmentRoot = [System.IO.Path]::GetFullPath(
    (Get-RoboticsEnvironmentRoot -RepositoryRoot $repositoryRoot)
)
$localAppDataRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $env:LOCALAPPDATA "RoboticsProgrammingLab")
).TrimEnd('\')
$repositoryPrefix = "$($repositoryRoot.TrimEnd('\'))\"
$localPrefix = "$localAppDataRoot\"

if ($environmentRoot.StartsWith($repositoryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The Python environment must not be stored inside the repository."
}
if (-not $environmentRoot.StartsWith($localPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The Python environment must stay under the RoboticsProgrammingLab LocalAppData root."
}

$python = Get-RoboticsPythonExecutable -RepositoryRoot $repositoryRoot
$expectedPython = Join-Path $environmentRoot "Scripts\python.exe"
if (-not $python.Equals($expectedPython, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "The resolved Python executable is not in the device-local environment."
}

$cacheRoot = [System.Environment]::GetEnvironmentVariable("PYTHONPYCACHEPREFIX", "Process")
if ([string]::IsNullOrWhiteSpace($cacheRoot)) {
    throw "PYTHONPYCACHEPREFIX was not configured."
}
$resolvedCache = [System.IO.Path]::GetFullPath($cacheRoot)
if (-not $resolvedCache.StartsWith($localPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Python bytecode cache must stay under LocalAppData."
}

$packageRoot = [System.IO.Path]::GetFullPath(
    (Get-RoboticsHandoffPackageRoot -RepositoryRoot $repositoryRoot)
)
$configPath = [System.IO.Path]::GetFullPath(
    (Get-RoboticsHandoffPrivateConfigPath -RepositoryRoot $repositoryRoot)
)
$expectedConfigPath = Join-Path $packageRoot ".env"
if (-not $configPath.Equals(
    [System.IO.Path]::GetFullPath($expectedConfigPath),
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "The package root .env file is not the active private configuration path."
}

Write-Output "PASS: generated Python environment and bytecode cache remain device-local."
Write-Output "PASS: private Neon configuration remains in the expected ignored package folder."
Write-Output "Python environment: $environmentRoot"
Write-Output "Python cache: $resolvedCache"
Write-Output "Private config: $configPath"
