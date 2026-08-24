$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
Import-Module (Join-Path $PSScriptRoot "local-environment.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "local-database.psm1") -Force
$python = Get-RoboticsPythonExecutable -RepositoryRoot $repositoryRoot

$testId = [guid]::NewGuid().ToString("N")
$testRoot = Join-Path $env:TEMP "robotics-db-handoff-$testId"
$backupRoot = Join-Path $testRoot "backups"
$runtimeOne = Join-Path $testRoot "runtime-one"
$runtimeTwo = Join-Path $testRoot "runtime-two"
$projectName = "robotics-lab-handoff-test-$($testId.Substring(0, 10))"
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$databasePort = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
$listener.Stop()
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null

function Get-ApplicationTableCounts {
    param([Parameter(Mandatory = $true)][string]$DatabaseUrl)
    $code = "import json,sys; from database import build_engine; from database_transfer import table_counts; print(json.dumps(table_counts(build_engine(sys.argv[1])), sort_keys=True))"
    $previousDatabaseUrl = [Environment]::GetEnvironmentVariable("DATABASE_URL", "Process")
    [Environment]::SetEnvironmentVariable("DATABASE_URL", $DatabaseUrl, "Process")
    Push-Location (Join-Path $repositoryRoot "backend")
    try {
        $result = & $python -c $code $DatabaseUrl
        if ($LASTEXITCODE -ne 0) { throw "Database count inspection failed." }
        return $result.Trim()
    } finally {
        Pop-Location
        [Environment]::SetEnvironmentVariable("DATABASE_URL", $previousDatabaseUrl, "Process")
    }
}

function Remove-TestDatabase {
    $previousPort = [Environment]::GetEnvironmentVariable("LOCAL_POSTGRES_PORT", "Process")
    $previousPassword = [Environment]::GetEnvironmentVariable("LOCAL_POSTGRES_PASSWORD", "Process")
    try {
        [Environment]::SetEnvironmentVariable("LOCAL_POSTGRES_PORT", [string]$databasePort, "Process")
        [Environment]::SetEnvironmentVariable("LOCAL_POSTGRES_PASSWORD", "robotics-local-only", "Process")
        & docker compose --project-name $projectName --file (Join-Path $repositoryRoot "docker-compose.yml") down --volumes 2>$null | Out-Null
    } finally {
        [Environment]::SetEnvironmentVariable("LOCAL_POSTGRES_PORT", $previousPort, "Process")
        [Environment]::SetEnvironmentVariable("LOCAL_POSTGRES_PASSWORD", $previousPassword, "Process")
    }
}

try {
    $first = Start-RoboticsLocalPostgres `
        -RepositoryRoot $repositoryRoot `
        -DatabasePort $databasePort `
        -ProjectName $projectName `
        -BackupRoot $backupRoot `
        -RuntimeRoot $runtimeOne

    $originalComputerName = $env:COMPUTERNAME
    try {
        $env:COMPUTERNAME = "SECOND-DEVICE-TEST"
        $secondDeviceWasBlocked = $false
        try {
            Start-RoboticsLocalPostgres `
                -RepositoryRoot $repositoryRoot `
                -DatabasePort $databasePort `
                -ProjectName $projectName `
                -BackupRoot $backupRoot `
                -RuntimeRoot $runtimeTwo | Out-Null
        } catch {
            if ($_.Exception.Message -like "*database is assigned to*") {
                $secondDeviceWasBlocked = $true
            } else {
                throw
            }
        }
        if (-not $secondDeviceWasBlocked) {
            throw "The device lock did not block a simulated second computer."
        }
    } finally {
        $env:COMPUTERNAME = $originalComputerName
    }

    $previousUrl = [Environment]::GetEnvironmentVariable("DATABASE_URL", "Process")
    [Environment]::SetEnvironmentVariable("DATABASE_URL", $first.DatabaseUrl, "Process")
    Push-Location (Join-Path $repositoryRoot "backend")
    try {
        & $python -m alembic upgrade head
        if ($LASTEXITCODE -ne 0) { throw "PostgreSQL migration failed." }
        & $python database_transfer.py `
            --sqlite robotics_lab_staging.db `
            --target-url $first.DatabaseUrl `
            --if-empty | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "SQLite transfer failed." }
    } finally {
        Pop-Location
        [Environment]::SetEnvironmentVariable("DATABASE_URL", $previousUrl, "Process")
    }
    $sourceUrl = "sqlite:///$((Join-Path $repositoryRoot 'backend\robotics_lab_staging.db').Replace('\', '/'))"
    $sourceCounts = Get-ApplicationTableCounts -DatabaseUrl $sourceUrl

    Complete-RoboticsLocalPostgres `
        -RepositoryRoot $repositoryRoot `
        -SessionId $first.SessionId `
        -DatabasePort $databasePort `
        -ProjectName $projectName `
        -BackupRoot $backupRoot `
        -RuntimeRoot $runtimeOne | Out-Host

    foreach ($required in @("latest.dump", "latest.json")) {
        if (-not (Test-Path -LiteralPath (Join-Path $backupRoot $required))) {
            throw "Expected synchronized artifact is missing: $required"
        }
    }
    if (Test-Path -LiteralPath (Join-Path $backupRoot "active-device.json")) {
        throw "The first device lock was not released."
    }

    $latestDump = Join-Path $backupRoot "latest.dump"
    $verifiedCopy = Join-Path $runtimeOne "verified-latest.dump"
    Copy-Item -LiteralPath $latestDump -Destination $verifiedCopy -Force
    [System.IO.File]::AppendAllText($latestDump, "checksum-test")
    $checksumMismatchWasBlocked = $false
    try {
        Start-RoboticsLocalPostgres `
            -RepositoryRoot $repositoryRoot `
            -DatabasePort $databasePort `
            -ProjectName $projectName `
            -BackupRoot $backupRoot `
            -RuntimeRoot $runtimeTwo | Out-Null
    } catch {
        if ($_.Exception.Message -like "*checksum does not match*") {
            $checksumMismatchWasBlocked = $true
        } else {
            throw
        }
    }
    if (-not $checksumMismatchWasBlocked) {
        throw "A modified synchronized backup was not rejected."
    }
    Copy-Item -LiteralPath $verifiedCopy -Destination $latestDump -Force

    Remove-TestDatabase

    $sameDevice = Start-RoboticsLocalPostgres `
        -RepositoryRoot $repositoryRoot `
        -DatabasePort $databasePort `
        -ProjectName $projectName `
        -BackupRoot $backupRoot `
        -RuntimeRoot $runtimeOne
    if (-not $sameDevice.RestoredBackup) {
        throw "Same-device Docker volume loss did not restore the synchronized backup."
    }
    $sameDeviceCounts = Get-ApplicationTableCounts -DatabaseUrl $sameDevice.DatabaseUrl
    if ($sourceCounts -ne $sameDeviceCounts) {
        throw "Same-device restored row counts differ. Source=$sourceCounts Restored=$sameDeviceCounts"
    }
    Complete-RoboticsLocalPostgres `
        -RepositoryRoot $repositoryRoot `
        -SessionId $sameDevice.SessionId `
        -DatabasePort $databasePort `
        -ProjectName $projectName `
        -BackupRoot $backupRoot `
        -RuntimeRoot $runtimeOne | Out-Host

    Remove-TestDatabase

    $second = Start-RoboticsLocalPostgres `
        -RepositoryRoot $repositoryRoot `
        -DatabasePort $databasePort `
        -ProjectName $projectName `
        -BackupRoot $backupRoot `
        -RuntimeRoot $runtimeTwo
    if (-not $second.RestoredBackup) {
        throw "A new-device database did not restore the synchronized backup."
    }
    $restoredCounts = Get-ApplicationTableCounts -DatabaseUrl $second.DatabaseUrl
    if ($sourceCounts -ne $restoredCounts) {
        throw "Restored row counts differ. Source=$sourceCounts Restored=$restoredCounts"
    }

    Complete-RoboticsLocalPostgres `
        -RepositoryRoot $repositoryRoot `
        -SessionId $second.SessionId `
        -DatabasePort $databasePort `
        -ProjectName $projectName `
        -BackupRoot $backupRoot `
        -RuntimeRoot $runtimeTwo | Out-Host
    Write-Output "PASS: SQLite migration, PostgreSQL backup, checksum, lock release, same-device recovery, and clean-device restore preserved every application table count."
    Write-Output $restoredCounts
} finally {
    Remove-TestDatabase
    $resolvedTemp = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
    $resolvedTest = [System.IO.Path]::GetFullPath($testRoot)
    if ($resolvedTest.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTest)) {
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force
    }
}
