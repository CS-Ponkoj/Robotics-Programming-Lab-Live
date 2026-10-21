# Stops the processes started by run-live.ps1. PostgreSQL keeps running in
# Docker so other tools can still reach the data.

$patterns = @(
    'uvicorn app:app',
    'serve_web\.py',
    'Caddyfile\.live',
    'cloudflared(\.exe)?"? tunnel run rpl-live'
)
Get-CimInstance Win32_Process |
    Where-Object { $commandLine = $_.CommandLine; $commandLine -and ($patterns | Where-Object { $commandLine -match $_ }) } |
    ForEach-Object {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Output "Stopped $($_.Name) ($($_.ProcessId))"
    }
