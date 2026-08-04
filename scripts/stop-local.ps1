$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$stateFile = Join-Path $repositoryRoot ".local-run\state.json"

if (-not (Test-Path -LiteralPath $stateFile)) {
    Write-Output "No managed local Robotics Programming Lab processes are recorded."
    exit 0
}

$state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
foreach ($entry in @($state.processes | Sort-Object { if ($_.name -eq "frontend") { 0 } else { 1 } })) {
    $process = Get-Process -Id $entry.id -ErrorAction SilentlyContinue
    if ($process) {
        & taskkill.exe /PID $entry.id /T /F 2>$null | Out-Null
        Write-Output "Stopped $($entry.name) process $($entry.id)."
    }
}

Remove-Item -LiteralPath $stateFile -Force
Write-Output "Local Robotics Programming Lab services are stopped."
