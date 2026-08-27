param(
    [Parameter(Mandatory = $true)][string]$SessionId,
    [int]$DatabasePort = 5432,
    [string]$ProjectName = "robotics-lab-local",
    [Parameter(Mandatory = $true)][string]$BackupRoot,
    [Parameter(Mandatory = $true)][string]$RuntimeRoot,
    [ValidateRange(1, 1440)][int]$IntervalMinutes = 10,
    [switch]$RunOnce
)

$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
Import-Module (Join-Path $PSScriptRoot "local-database.psm1") -Force

function Save-CurrentDatabase {
    $result = Save-RoboticsLocalPostgresBackup `
        -RepositoryRoot $repositoryRoot `
        -SessionId $SessionId `
        -DatabasePort $DatabasePort `
        -ProjectName $ProjectName `
        -BackupRoot $BackupRoot `
        -RuntimeRoot $RuntimeRoot `
        -SkipIfUnchanged `
        -MutexTimeoutSeconds 30
    if ($result.Saved) {
        Write-Output "[$([DateTime]::UtcNow.ToString('o'))] Verified automatic PostgreSQL backup saved."
    } else {
        Write-Output "[$([DateTime]::UtcNow.ToString('o'))] Database unchanged; automatic backup skipped."
    }
}

Save-CurrentDatabase
if ($RunOnce) { exit 0 }

while ($true) {
    Start-Sleep -Seconds ($IntervalMinutes * 60)
    try {
        Save-CurrentDatabase
    } catch {
        Write-Error "Automatic PostgreSQL backup failed: $_" -ErrorAction Continue
    }
}
