<#
.SYNOPSIS
Store or remove a secret for the self-hosted live stack (RPL Live).

.DESCRIPTION
The value is typed at a hidden prompt, encrypted with Windows DPAPI for the
current Windows user, and stored under LocalAppData, outside the Git clone.
run-live.ps1 gives it to the API process only. The value is never printed.
Restart the stack (stop-live.ps1, then run-live.ps1 -SkipBuild) to apply it.

.EXAMPLE
.\scripts\set-live-secret.ps1
.\scripts\set-live-secret.ps1 -Remove
#>
param(
    [ValidateSet("OPENAI_API_KEY")]
    [string]$Name = "OPENAI_API_KEY",
    [switch]$Remove
)
$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "local-environment.psm1") -Force

$path = Get-RoboticsLiveSecretPath -Name $Name
if ($Remove) {
    if (Test-Path $path) { Remove-Item -Path $path -Force }
    Write-Output "$Name removed. Restart the live stack to apply."
    return
}
$value = Read-Host "Paste $Name (hidden)" -AsSecureString
if ($value.Length -eq 0) { throw "No value entered; nothing was stored." }
Write-RoboticsLiveSecret -Name $Name -Value $value
Write-Output "$Name stored for this Windows user. Restart the live stack to apply."
