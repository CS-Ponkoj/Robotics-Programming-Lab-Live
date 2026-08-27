$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
Import-Module (Join-Path $PSScriptRoot "local-environment.psm1") -Force
$runtimeRoot = Get-RoboticsRuntimeRoot -RepositoryRoot $repositoryRoot
$stateFile = Join-Path $runtimeRoot "state.json"

if (-not (Test-Path -LiteralPath $stateFile)) {
    Write-Output "No managed local Robotics Programming Lab processes are recorded."
    exit 0
}

$state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
foreach ($entry in @($state.processes | Sort-Object {
    if ($_.name -eq "database-backup") { 0 }
    elseif ($_.name -eq "frontend") { 1 }
    else { 2 }
})) {
    $process = Get-Process -Id $entry.id -ErrorAction SilentlyContinue
    if ($process) {
        & taskkill.exe /PID $entry.id /T /F 2>$null | Out-Null
        Write-Output "Stopped $($entry.name) process $($entry.id)."
    }
}

if ($state.managedLocalDatabase) {
    Import-Module (Join-Path $PSScriptRoot "local-database.psm1") -Force
    Complete-RoboticsLocalPostgres `
        -RepositoryRoot $repositoryRoot `
        -SessionId $state.localDatabaseSessionId `
        -DatabasePort $state.localDatabasePort `
        -ProjectName $state.localDatabaseProjectName `
        -BackupRoot $state.localDatabaseBackupRoot `
        -RuntimeRoot $state.localDatabaseRuntimeRoot | Out-Host
}

Remove-Item -LiteralPath $stateFile -Force
Write-Output "Local Robotics Programming Lab services are stopped."
