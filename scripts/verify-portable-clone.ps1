$ErrorActionPreference = "Stop"
$sourceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$testParent = Join-Path $env:TEMP ("robotics-clone-package-" + [guid]::NewGuid().ToString("N"))
$testClone = Join-Path $testParent "Robotics-Programming-Lab-Staging"
$separator = [System.IO.Path]::DirectorySeparatorChar
$safeTemp = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd($separator)

try {
    New-Item -ItemType Directory -Force -Path $testParent | Out-Null
    & git -c core.longpaths=true clone --quiet --no-hardlinks $sourceRoot $testClone
    if ($LASTEXITCODE -ne 0) { throw "Temporary clone failed." }
    & git -C $testClone config core.longpaths true
    if ($LASTEXITCODE -ne 0) { throw "Windows long-path support could not be saved in the temporary clone." }
    if ((git -C $testClone config --get core.longpaths) -ne "true") {
        throw "The temporary clone did not retain Windows long-path support."
    }

    git -C $sourceRoot diff --binary HEAD |
        & git -C $testClone apply --whitespace=nowarn -
    if ($LASTEXITCODE -ne 0) {
        throw "The current working-tree patch could not be applied to the temporary clone."
    }

    $untracked = @(git -C $sourceRoot ls-files --others --exclude-standard)
    foreach ($relativePath in $untracked) {
        $source = Join-Path $sourceRoot $relativePath
        $destination = Join-Path $testClone $relativePath
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }

    $sourcePackage = Join-Path $sourceRoot "local_handoff_package"
    $destinationPackage = Join-Path $testClone "local_handoff_package"
    New-Item -ItemType Directory -Force -Path $destinationPackage | Out-Null
    Get-ChildItem -LiteralPath $sourcePackage -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $destinationPackage -Recurse -Force
    }

    Push-Location $testClone
    try {
        & (Join-Path $testClone "scripts\setup-local.ps1") | Out-Host
        Import-Module (Join-Path $testClone "scripts\local-environment.psm1") -Force
        $resolvedBackup = Get-RoboticsDatabaseBackupRoot -RepositoryRoot $testClone
        $expectedBackup = Join-Path $testClone "local_handoff_package"
        if (-not [System.IO.Path]::GetFullPath($resolvedBackup).Equals(
            [System.IO.Path]::GetFullPath($expectedBackup),
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "The temporary clone did not select the pasted handoff database."
        }

        $packagedConfig = Join-Path $testClone "local_handoff_package\.env"
        $installedConfig = Join-Path $testClone "backend\.env"
        if (Test-Path -LiteralPath $packagedConfig) {
            if (Test-Path -LiteralPath $installedConfig) {
                throw "The temporary clone created a duplicate backend/.env file."
            }
        }
        & (Join-Path $testClone "scripts\verify-local-handoff-package.ps1") | Out-Host
    } finally {
        Pop-Location
    }
    Write-Output "PASS: a fresh-clone simulation used the package database and private configuration directly."
} finally {
    if (Test-Path -LiteralPath $testParent) {
        $resolvedParent = [System.IO.Path]::GetFullPath($testParent)
        if (-not $resolvedParent.StartsWith(
            "$safeTemp$separator",
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            throw "Refusing to remove an unexpected temporary clone path."
        }
        Remove-Item -LiteralPath $resolvedParent -Recurse -Force
    }
}
