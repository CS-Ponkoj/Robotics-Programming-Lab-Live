$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
Import-Module (Join-Path $PSScriptRoot "local-environment.psm1") -Force

$packageRoot = Get-RoboticsHandoffPackageRoot -RepositoryRoot $repositoryRoot
$configPath = Get-RoboticsHandoffPrivateConfigPath -RepositoryRoot $repositoryRoot
$accountsPath = Join-Path $repositoryRoot "backend\data\study_accounts.json"

foreach ($required in @($configPath, $accountsPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required private staging file is missing: $required"
    }
}

$neonConfigured = $false
foreach ($line in [System.IO.File]::ReadLines($configPath)) {
    if ($line -match '^\s*NEON_DATABASE_URL\s*=\s*(.+)\s*$') {
        $value = $Matches[1].Trim().Trim('"').Trim("'")
        $neonConfigured = $value.StartsWith("postgres") -and $value.Contains(".neon.tech")
        break
    }
}
if (-not $neonConfigured) {
    throw "NEON_DATABASE_URL is missing or invalid in local_handoff_package/.env."
}

$trackedPrivateFiles = @(git -C $repositoryRoot ls-files -- "local_handoff_package/.env")
if ($trackedPrivateFiles.Count -gt 0) {
    throw "Private staging files must not be tracked by Git."
}

$ignoredAccounts = @(git -C $repositoryRoot check-ignore -- "backend/data/study_accounts.json")
if ($ignoredAccounts.Count -gt 0) {
    throw "The password-free account roster must be eligible for Git tracking."
}

$accounts = Get-Content -LiteralPath $accountsPath -Raw | ConvertFrom-Json
$passwordRows = @($accounts.accounts | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_.temporary_password)
})
if ($passwordRows.Count -gt 0) {
    throw "Tracked study_accounts.json must not contain temporary passwords. Use Instructor Studio for passwords."
}

$obsoleteNames = @(
    "history",
    "latest.dump",
    "latest.json",
    "previous.dump",
    "previous.json",
    "package.json",
    "neon-migration-report.json",
    "study_accounts_import_report.json"
)
$obsoletePresent = @($obsoleteNames | Where-Object {
    Test-Path -LiteralPath (Join-Path $packageRoot $_)
})
if ($obsoletePresent.Count -gt 0) {
    throw "Obsolete local-database artifacts remain: $($obsoletePresent -join ', ')"
}

Write-Output "PASS: Neon configuration is private, the password-free account roster is tracked, and obsolete local-database artifacts are absent."
