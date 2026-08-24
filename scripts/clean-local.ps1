[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path.TrimEnd('\')
$repoPrefix = "$repoRoot\"

$protectedRoots = @(
    (Join-Path $repoRoot '.git'),
    (Join-Path $repoRoot 'venv'),
    (Join-Path $repoRoot 'backend\data'),
    (Join-Path $repoRoot 'course_materials'),
    (Join-Path $repoRoot 'manual_sqa_answers'),
    (Join-Path $repoRoot 'local_database_backups'),
    (Join-Path $repoRoot 'output')
)

$relativeTargets = @(
    '.local-run',
    '.pytest_cache',
    '.vs',
    'frontend\.dart_tool',
    'frontend\.flutter_build',
    'frontend\.flutter-plugins-dependencies',
    'frontend\build',
    'backend\.pytest_cache'
)

$targetPaths = [System.Collections.Generic.List[string]]::new()
foreach ($relativePath in $relativeTargets) {
    $candidate = Join-Path $repoRoot $relativePath
    if (Test-Path -LiteralPath $candidate) {
        $targetPaths.Add((Get-Item -LiteralPath $candidate -Force).FullName)
    }
}

$backendRoot = Join-Path $repoRoot 'backend'
if (Test-Path -LiteralPath $backendRoot) {
    Get-ChildItem -LiteralPath $backendRoot -Recurse -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object Name -eq '__pycache__' |
        ForEach-Object { $targetPaths.Add($_.FullName) }
}

$targets = $targetPaths | Sort-Object -Unique
$validatedTargets = foreach ($target in $targets) {
    $fullPath = [System.IO.Path]::GetFullPath($target)
    if (-not $fullPath.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Cleanup target is outside the repository: $fullPath"
    }

    foreach ($protectedRoot in $protectedRoots) {
        $protectedFullPath = [System.IO.Path]::GetFullPath($protectedRoot).TrimEnd('\')
        if (
            $fullPath.Equals($protectedFullPath, [System.StringComparison]::OrdinalIgnoreCase) -or
            $fullPath.StartsWith("$protectedFullPath\", [System.StringComparison]::OrdinalIgnoreCase)
        ) {
            throw "Cleanup target is protected: $fullPath"
        }
    }

    $item = Get-Item -LiteralPath $fullPath -Force
    $sizeBytes = if ($item.PSIsContainer) {
        (Get-ChildItem -LiteralPath $fullPath -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
    } else {
        $item.Length
    }
    if ($null -eq $sizeBytes) {
        $sizeBytes = 0
    }

    [pscustomobject]@{
        Path = $fullPath
        SizeBytes = [long]$sizeBytes
    }
}

if (-not $validatedTargets) {
    Write-Host 'No approved generated artifacts were found.'
    return
}

$totalBytes = ($validatedTargets | Measure-Object -Property SizeBytes -Sum).Sum
$validatedTargets |
    Select-Object @{Name = 'SizeMB'; Expression = { [math]::Round($_.SizeBytes / 1MB, 2) } }, Path |
    Format-Table -AutoSize

if (-not $Execute) {
    Write-Host "Dry run only. $($validatedTargets.Count) target(s), $([math]::Round($totalBytes / 1MB, 2)) MB total."
    Write-Host 'Run .\scripts\clean-local.ps1 -Execute after stopping the application.'
    return
}

$activePorts = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object LocalPort -in @(5100, 5101, 8180)
if ($activePorts) {
    throw 'The local application is still running on port 5100, 5101, or 8180. Stop it before cleanup.'
}

foreach ($target in $validatedTargets) {
    if ($PSCmdlet.ShouldProcess($target.Path, 'Remove approved generated artifact')) {
        if (Test-Path -LiteralPath $target.Path -PathType Container) {
            Get-ChildItem -LiteralPath $target.Path -Recurse -Force -ErrorAction SilentlyContinue |
                ForEach-Object {
                    if (-not $_.PSIsContainer -and $_.IsReadOnly) {
                        $_.IsReadOnly = $false
                    }
                }
            Remove-Item -LiteralPath $target.Path -Recurse -Force
        } else {
            $file = Get-Item -LiteralPath $target.Path -Force
            if ($file.IsReadOnly) {
                $file.IsReadOnly = $false
            }
            Remove-Item -LiteralPath $target.Path -Force
        }
    }
}

$remaining = $validatedTargets | Where-Object { Test-Path -LiteralPath $_.Path }
if ($remaining) {
    $remaining.Path | ForEach-Object { Write-Error "Cleanup target remains: $_" }
    throw 'One or more approved cleanup targets could not be removed.'
}

Write-Host "Removed $($validatedTargets.Count) generated target(s), approximately $([math]::Round($totalBytes / 1MB, 2)) MB."
Write-Host 'Protected environments, databases, backups, outputs, course materials, and instructor answers were not touched.'
