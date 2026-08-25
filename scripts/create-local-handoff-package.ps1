param([switch]$IncludePrivateConfig)

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
        throw "Stop the local application before creating the handoff package: .\scripts\stop-local.ps1"
    }
}

$packageRoot = Get-RoboticsHandoffPackageRoot -RepositoryRoot $repositoryRoot
$destinationDatabase = Get-RoboticsHandoffDatabaseRoot -RepositoryRoot $repositoryRoot
$legacyDatabase = Join-Path $packageRoot "database"
$legacyDump = Join-Path $legacyDatabase "latest.dump"
$legacyManifest = Join-Path $legacyDatabase "latest.json"
$destinationDump = Join-Path $destinationDatabase "latest.dump"
$destinationManifest = Join-Path $destinationDatabase "latest.json"

# One-time migration from the earlier nested package layout. The source pair is
# checksum-verified before it becomes the package's active root-level backup.
if (-not (Test-Path -LiteralPath $destinationDump) -and
    -not (Test-Path -LiteralPath $destinationManifest) -and
    (Test-Path -LiteralPath $legacyDump) -and
    (Test-Path -LiteralPath $legacyManifest)) {
    $legacyInfo = Get-Content -LiteralPath $legacyManifest -Raw | ConvertFrom-Json
    $legacyHash = (Get-FileHash -LiteralPath $legacyDump -Algorithm SHA256).Hash
    if ([string]::IsNullOrWhiteSpace($legacyInfo.sha256) -or $legacyHash -ne $legacyInfo.sha256) {
        throw "The legacy handoff backup failed checksum verification. Nothing was migrated."
    }
    Copy-Item -LiteralPath $legacyDump -Destination $destinationDump -Force
    Copy-Item -LiteralPath $legacyManifest -Destination $destinationManifest -Force
    foreach ($name in @("previous.dump", "previous.json")) {
        $legacyFile = Join-Path $legacyDatabase $name
        if (Test-Path -LiteralPath $legacyFile) {
            Copy-Item -LiteralPath $legacyFile -Destination (Join-Path $destinationDatabase $name) -Force
        }
    }
}

$sourceDatabase = Get-RoboticsDatabaseBackupRoot -RepositoryRoot $repositoryRoot
$sourceDump = Join-Path $sourceDatabase "latest.dump"
$sourceManifest = Join-Path $sourceDatabase "latest.json"
if (-not (Test-Path -LiteralPath $sourceDump) -or -not (Test-Path -LiteralPath $sourceManifest)) {
    throw "No complete verified database backup is available. Start and stop the application once, then try again."
}

$manifest = Get-Content -LiteralPath $sourceManifest -Raw | ConvertFrom-Json
$sourceHash = (Get-FileHash -LiteralPath $sourceDump -Algorithm SHA256).Hash
if ([string]::IsNullOrWhiteSpace($manifest.sha256) -or $sourceHash -ne $manifest.sha256) {
    throw "The current database backup failed checksum verification. The handoff package was not changed."
}

New-Item -ItemType Directory -Force -Path $packageRoot, $destinationDatabase | Out-Null
$sameDatabase = [System.IO.Path]::GetFullPath($sourceDatabase).Equals(
    [System.IO.Path]::GetFullPath($destinationDatabase),
    [System.StringComparison]::OrdinalIgnoreCase
)
if (-not $sameDatabase) {
    $incomingDump = Join-Path $destinationDatabase "latest.dump.incoming"
    $incomingManifest = Join-Path $destinationDatabase "latest.json.incoming"
    Copy-Item -LiteralPath $sourceDump -Destination $incomingDump -Force
    Copy-Item -LiteralPath $sourceManifest -Destination $incomingManifest -Force
    if ((Get-FileHash -LiteralPath $incomingDump -Algorithm SHA256).Hash -ne $sourceHash) {
        Remove-Item -LiteralPath $incomingDump, $incomingManifest -Force -ErrorAction SilentlyContinue
        throw "The copied database backup failed checksum verification."
    }
    Move-Item -LiteralPath $incomingDump -Destination (Join-Path $destinationDatabase "latest.dump") -Force
    Move-Item -LiteralPath $incomingManifest -Destination (Join-Path $destinationDatabase "latest.json") -Force

    $previousDump = Join-Path $sourceDatabase "previous.dump"
    $previousManifest = Join-Path $sourceDatabase "previous.json"
    if ((Test-Path -LiteralPath $previousDump) -and (Test-Path -LiteralPath $previousManifest)) {
        $previousInfo = Get-Content -LiteralPath $previousManifest -Raw | ConvertFrom-Json
        $previousHash = (Get-FileHash -LiteralPath $previousDump -Algorithm SHA256).Hash
        if (-not [string]::IsNullOrWhiteSpace($previousInfo.sha256) -and $previousHash -eq $previousInfo.sha256) {
            Copy-Item -LiteralPath $previousDump -Destination (Join-Path $destinationDatabase "previous.dump") -Force
            Copy-Item -LiteralPath $previousManifest -Destination (Join-Path $destinationDatabase "previous.json") -Force
        }
    }
}

$packagedConfig = Get-RoboticsHandoffPrivateConfigPath -RepositoryRoot $repositoryRoot
$backendConfig = Join-Path $repositoryRoot "backend\.env"
$legacyConfig = Join-Path $packageRoot "private\backend.env"
if ($IncludePrivateConfig) {
    if (Test-Path -LiteralPath $backendConfig) {
        Copy-Item -LiteralPath $backendConfig -Destination $packagedConfig -Force
    } elseif (-not (Test-Path -LiteralPath $packagedConfig) -and (Test-Path -LiteralPath $legacyConfig)) {
        Copy-Item -LiteralPath $legacyConfig -Destination $packagedConfig -Force
    } elseif (-not (Test-Path -LiteralPath $packagedConfig)) {
        Write-Warning "No private configuration exists, so local_handoff_package/.env was not created."
    } else {
        Write-Output "Keeping the existing local_handoff_package/.env file."
    }
}

$gitHead = (& git -C $repositoryRoot rev-parse HEAD 2>$null | Select-Object -Last 1)
$workingTreeDirty = [bool](@(git -C $repositoryRoot status --porcelain).Count)
[pscustomobject]@{
    schemaVersion = 1
    createdAtUtc = [DateTime]::UtcNow.ToString("o")
    sourceCommit = if ([string]::IsNullOrWhiteSpace($gitHead)) { $null } else { $gitHead.Trim() }
    sourceWorkingTreeDirty = $workingTreeDirty
    databaseSha256 = $sourceHash
    includesPrivateConfig = Test-Path -LiteralPath $packagedConfig
    includesPythonEnvironment = $false
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $packageRoot "package.json") -Encoding UTF8

Write-Output "Local handoff package is ready: $packageRoot"
Write-Output "Database checksum verified: $sourceHash"
Write-Output "Private configuration included: $(Test-Path -LiteralPath $packagedConfig)"
Write-Output "Python environment included: False (rebuilt safely on the destination computer)"
