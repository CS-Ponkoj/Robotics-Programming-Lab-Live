$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
Import-Module (Join-Path $PSScriptRoot "local-environment.psm1") -Force
$python = Get-RoboticsPythonExecutable -RepositoryRoot $repositoryRoot
& $python (Join-Path $PSScriptRoot "check_openai_api.py")
