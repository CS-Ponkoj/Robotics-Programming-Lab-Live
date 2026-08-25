$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "local-environment.psm1") -Force

$temporaryRoot = [System.IO.Path]::GetFullPath(
    (Join-Path ([System.IO.Path]::GetTempPath()) ("robotics-handoff-layout-" + [guid]::NewGuid().ToString("N")))
)
$separator = [System.IO.Path]::DirectorySeparatorChar
$safeTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd($separator)
if (-not $temporaryRoot.StartsWith("$safeTempRoot$separator", [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to use an unexpected test directory."
}

$testRepository = Join-Path $temporaryRoot "Robotics-Programming-Lab-Staging"
$packageRoot = Join-Path $testRepository "local_handoff_package"
$previousOverride = [System.Environment]::GetEnvironmentVariable("ROBOTICS_DATABASE_BACKUP_ROOT", "Process")

try {
    New-Item -ItemType Directory -Force -Path $testRepository, $packageRoot | Out-Null
    [System.Environment]::SetEnvironmentVariable("ROBOTICS_DATABASE_BACKUP_ROOT", $null, "Process")

    $withoutBackup = Get-RoboticsDatabaseBackupRoot -RepositoryRoot $testRepository
    if (-not $withoutBackup.Equals(
        [System.IO.Path]::GetFullPath($packageRoot),
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "The package root must remain the only default database location."
    }

    Set-Content -LiteralPath (Join-Path $packageRoot "latest.dump") -Value "test-dump" -NoNewline
    try {
        Get-RoboticsDatabaseBackupRoot -RepositoryRoot $testRepository | Out-Null
        throw "An incomplete handoff database package was accepted."
    } catch {
        if ($_.Exception.Message -notmatch "incomplete") { throw }
    }
    Set-Content -LiteralPath (Join-Path $packageRoot "latest.json") -Value "{}" -NoNewline
    $withBackup = Get-RoboticsDatabaseBackupRoot -RepositoryRoot $testRepository
    if (-not $withBackup.Equals(
        [System.IO.Path]::GetFullPath($packageRoot),
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "The complete handoff database was not selected from the package root."
    }

    $configPath = Get-RoboticsHandoffPrivateConfigPath -RepositoryRoot $testRepository
    $expectedConfig = Join-Path $packageRoot ".env"
    if (-not $configPath.Equals(
        [System.IO.Path]::GetFullPath($expectedConfig),
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "The package root .env file was not selected."
    }
} finally {
    [System.Environment]::SetEnvironmentVariable("ROBOTICS_DATABASE_BACKUP_ROOT", $previousOverride, "Process")
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}

Write-Output "PASS: one package root is used for database backups and private configuration."

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if (Test-RoboticsHandoffDatabase -RepositoryRoot $repositoryRoot) {
    $actualDatabase = Get-RoboticsHandoffDatabaseRoot -RepositoryRoot $repositoryRoot
    $actualDump = Join-Path $actualDatabase "latest.dump"
    $actualManifest = Get-Content -LiteralPath (Join-Path $actualDatabase "latest.json") -Raw | ConvertFrom-Json
    $actualHash = (Get-FileHash -LiteralPath $actualDump -Algorithm SHA256).Hash
    if ([string]::IsNullOrWhiteSpace($actualManifest.sha256) -or $actualHash -ne $actualManifest.sha256) {
        throw "The current local handoff package database checksum is invalid."
    }
    $packageInfo = Get-Content -LiteralPath (Join-Path $actualDatabase "package.json") -Raw | ConvertFrom-Json
    if ($packageInfo.includesPythonEnvironment -ne $false) {
        throw "The handoff package must not claim to contain a portable Python environment."
    }
    if (-not (Test-Path -LiteralPath (Get-RoboticsHandoffPrivateConfigPath -RepositoryRoot $repositoryRoot))) {
        throw "The current local handoff package is missing its root .env file."
    }
    Write-Output "PASS: current package database checksum, .env, and portability manifest are valid."
}
