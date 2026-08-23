Set-StrictMode -Version Latest

$script:RequiredPythonMajorMinor = "3.14"

function Get-RoboticsRuntimeRoot {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $repositoryName = Split-Path -Leaf ([System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\'))
    $safeRepositoryName = $repositoryName -replace '[^A-Za-z0-9._-]', '-'
    return Join-Path $env:LOCALAPPDATA "RoboticsProgrammingLab\runtime\$safeRepositoryName"
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

function Prepare-SharedEnvironmentForWrite {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$EnvironmentRoot
    )

    $expected = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot "venv")).TrimEnd('\')
    $target = [System.IO.Path]::GetFullPath($EnvironmentRoot).TrimEnd('\')
    if (-not $target.Equals($expected, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify an unexpected environment path: $target"
    }
    if (-not (Test-Path -LiteralPath $target)) {
        return
    }

    # OneDrive placeholders can retain read-only/unpinned attributes after a
    # device switch. Hydrate only this ignored environment and make it writable
    # before Python repairs it.
    & attrib.exe -R +P -U "$target\*" /S /D 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "OneDrive could not prepare the shared environment for repair. Wait for sync to finish and try again."
    }
    & attrib.exe -R +P -U $target 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "OneDrive could not make the shared environment writable."
    }
}

function Get-RoboticsPythonExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [switch]$EnsureDependencies,
        [switch]$RefreshDependencies
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot)
    $environmentRoot = Join-Path $root "venv"
    $python = Join-Path $environmentRoot "Scripts\python.exe"
    $requirements = Join-Path $root "backend\requirements.txt"
    $marker = Join-Path $environmentRoot ".environment.signature"
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
        $desiredSignature = "$requirementsHash|$env:COMPUTERNAME|$baseIdentity"
        $installedSignature = if (Test-Path -LiteralPath $marker) {
            (Get-Content -LiteralPath $marker -Raw).Trim()
        } else {
            ""
        }
        $desiredParts = $desiredSignature -split '\|', 5
        $installedParts = $installedSignature -split '\|', 5
        $environmentMoved = (
            $installedParts.Count -eq 5 -and
            (($installedParts[1..4] -join '|') -ne ($desiredParts[1..4] -join '|'))
        )

        if ($RefreshDependencies -or -not $environmentIsUsable) {
            Write-Host "Creating a clean shared Python 3.14 environment..."
            Prepare-SharedEnvironmentForWrite -RepositoryRoot $root -EnvironmentRoot $environmentRoot
            & $basePython -m venv --clear $environmentRoot
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $python)) {
                throw "The Python 3.14 environment could not be created at $environmentRoot."
            }
            $environmentIsUsable = $true
            $installedSignature = ""
        } elseif ($environmentMoved) {
            Write-Host "Rebinding the shared Python environment to this computer..."
            Prepare-SharedEnvironmentForWrite -RepositoryRoot $root -EnvironmentRoot $environmentRoot
            & $basePython -m venv --upgrade $environmentRoot
            if ($LASTEXITCODE -ne 0) {
                throw "The shared Python environment could not be rebound to this computer. Run .\scripts\setup-local.ps1 -Repair."
            }
        }

        if ($desiredSignature -ne $installedSignature) {
            Write-Host "Installing the pinned backend dependencies..."
            $pipArguments = @("-m", "pip", "install", "--disable-pip-version-check")
            if ($RefreshDependencies -or $environmentMoved) {
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
            throw "The shared environment is incomplete. Run .\scripts\setup-local.ps1 -Repair."
        }
    } elseif (-not $environmentIsUsable) {
        throw "The shared Python 3.14 environment is missing or incompatible. Run: .\scripts\setup-local.ps1 -Repair"
    }

    return $python
}

Export-ModuleMember -Function Get-RoboticsRuntimeRoot, Get-RoboticsPythonExecutable
