Set-StrictMode -Version Latest

$script:RequiredPythonMajorMinor = "3.14"

function Get-RoboticsProjectKey {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $repositoryName = Split-Path -Leaf ([System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\'))
    return $repositoryName -replace '[^A-Za-z0-9._-]', '-'
}

function Get-RoboticsRuntimeRoot {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $projectKey = Get-RoboticsProjectKey -RepositoryRoot $RepositoryRoot
    return Join-Path $env:LOCALAPPDATA "RoboticsProgrammingLab\runtime\$projectKey"
}

function Get-RoboticsEnvironmentRoot {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $projectKey = Get-RoboticsProjectKey -RepositoryRoot $RepositoryRoot
    return Join-Path $env:LOCALAPPDATA "RoboticsProgrammingLab\environments\$projectKey\venv"
}

function Get-RoboticsHandoffPackageRoot {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    return Join-Path ([System.IO.Path]::GetFullPath($RepositoryRoot)) "local_handoff_package"
}

function Get-RoboticsHandoffDatabaseRoot {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    return Get-RoboticsHandoffPackageRoot -RepositoryRoot $RepositoryRoot
}

function Get-RoboticsHandoffPrivateConfigPath {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    return Join-Path (Get-RoboticsHandoffPackageRoot -RepositoryRoot $RepositoryRoot) ".env"
}

function Test-RoboticsHandoffDatabase {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $databaseRoot = Get-RoboticsHandoffDatabaseRoot -RepositoryRoot $RepositoryRoot
    $dumpExists = Test-Path -LiteralPath (Join-Path $databaseRoot "latest.dump")
    $manifestExists = Test-Path -LiteralPath (Join-Path $databaseRoot "latest.json")
    if ($dumpExists -xor $manifestExists) {
        throw "The local handoff package database is incomplete. Copy both latest.dump and latest.json."
    }
    return ($dumpExists -and $manifestExists)
}

function Get-RoboticsDatabaseBackupRoot {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [string]$ExplicitPath = ""
    )

    $configuredPath = if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $ExplicitPath
    } elseif (-not [string]::IsNullOrWhiteSpace($env:ROBOTICS_DATABASE_BACKUP_ROOT)) {
        $env:ROBOTICS_DATABASE_BACKUP_ROOT
    } else {
        ""
    }
    if (-not [string]::IsNullOrWhiteSpace($configuredPath)) {
        $expanded = [System.Environment]::ExpandEnvironmentVariables($configuredPath)
        return [System.IO.Path]::GetFullPath($expanded)
    }

    Test-RoboticsHandoffDatabase -RepositoryRoot $RepositoryRoot | Out-Null
    return Get-RoboticsHandoffDatabaseRoot -RepositoryRoot $RepositoryRoot
}

function Get-Python314BaseExecutable {
    $launcher = Get-Command py -ErrorAction SilentlyContinue
    if (-not $launcher) {
        throw "Python 3.14 is required. Install Python 3.14, reopen PowerShell, and run this command again."
    }

    $executable = (& $launcher.Source -3.14 -c "import sys; print(sys.executable)" 2>$null | Select-Object -Last 1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($executable)) {
        throw "Python 3.14 is required. Install it from python.org, reopen PowerShell, and run this command again."
    }
    return $executable.Trim()
}

function Prepare-LocalEnvironmentForWrite {
    param([Parameter(Mandatory = $true)][string]$EnvironmentRoot)

    $expectedParent = [System.IO.Path]::GetFullPath(
        (Join-Path $env:LOCALAPPDATA "RoboticsProgrammingLab\environments")
    ).TrimEnd('\')
    $target = [System.IO.Path]::GetFullPath($EnvironmentRoot).TrimEnd('\')
    $safePrefix = "$expectedParent\"
    if (-not $target.StartsWith($safePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify an unexpected environment path: $target"
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
}

function Get-RoboticsPythonExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [switch]$EnsureDependencies,
        [switch]$RefreshDependencies
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $environmentRoot = Get-RoboticsEnvironmentRoot -RepositoryRoot $root
    $python = Join-Path $environmentRoot "Scripts\python.exe"
    $requirements = Join-Path $root "backend\requirements.txt"
    $marker = Join-Path $environmentRoot ".environment.signature"
    $pythonCacheRoot = Join-Path (Get-RoboticsRuntimeRoot -RepositoryRoot $root) "python-cache"
    New-Item -ItemType Directory -Force -Path $pythonCacheRoot | Out-Null
    [System.Environment]::SetEnvironmentVariable(
        "PYTHONPYCACHEPREFIX",
        $pythonCacheRoot,
        "Process"
    )
    $basePython = $null

    $environmentIsUsable = $false
    if (Test-Path -LiteralPath $python) {
        & $python -c "import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 14) else 1)" 2>$null
        $environmentIsUsable = ($LASTEXITCODE -eq 0)
    }

    if ($EnsureDependencies) {
        $basePython = Get-Python314BaseExecutable
        $baseIdentity = (& $basePython -c "import platform, sys; print(f'{sys.executable}|{platform.python_version()}|{platform.machine()}')").Trim()
        $requirementsHash = (Get-FileHash -LiteralPath $requirements -Algorithm SHA256).Hash
        $desiredSignature = "$requirementsHash|$baseIdentity"
        $installedSignature = if (Test-Path -LiteralPath $marker) {
            (Get-Content -LiteralPath $marker -Raw).Trim()
        } else {
            ""
        }

        if ($RefreshDependencies -or -not $environmentIsUsable) {
            Write-Host "Creating a clean device-local Python 3.14 environment..."
            Prepare-LocalEnvironmentForWrite -EnvironmentRoot $environmentRoot
            & $basePython -m venv --clear $environmentRoot
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $python)) {
                throw "The Python 3.14 environment could not be created at $environmentRoot."
            }
            $environmentIsUsable = $true
            $installedSignature = ""
        }

        if ($desiredSignature -ne $installedSignature) {
            Write-Host "Installing the pinned backend dependencies..."
            $pipArguments = @("-m", "pip", "install", "--disable-pip-version-check")
            if ($RefreshDependencies) {
                $pipArguments += @("--upgrade", "--force-reinstall", "--no-cache-dir")
            }
            $pipArguments += @("-r", $requirements)
            & $python @pipArguments 2>&1 | Out-Host
            if ($LASTEXITCODE -ne 0) {
                throw "Backend dependency installation failed."
            }
            Set-Content -LiteralPath $marker -Value $desiredSignature -Encoding UTF8 -NoNewline
        }

        & $python -c "import pydantic_core, _cffi_backend, numpy, scipy, psycopg"
        if ($LASTEXITCODE -ne 0) {
            throw "The device-local environment is incomplete. Run .\scripts\setup-local.ps1 -Repair."
        }
    } elseif (-not $environmentIsUsable) {
        throw "The device-local Python 3.14 environment is missing or incompatible. Run: .\scripts\setup-local.ps1 -Repair"
    }

    return $python
}

Export-ModuleMember -Function Get-RoboticsRuntimeRoot, Get-RoboticsEnvironmentRoot, Get-RoboticsHandoffPackageRoot, Get-RoboticsHandoffDatabaseRoot, Get-RoboticsHandoffPrivateConfigPath, Test-RoboticsHandoffDatabase, Get-RoboticsDatabaseBackupRoot, Get-RoboticsPythonExecutable
