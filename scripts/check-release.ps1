param(
    [switch]$AllowDirty,
    [switch]$SkipRemoteCheck
)

$ErrorActionPreference = "Stop"
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
Push-Location $repositoryRoot
try {
    if (-not $AllowDirty -and (git status --porcelain)) {
        throw "Release check requires a clean Git working tree."
    }

    $tracked = @(git ls-files)
    $forbidden = @($tracked | Where-Object {
        $_ -match '(^|/)(\.env|env|venv|venvs|build|\.dart_tool|\.local-run)(/|$)' -or
        $_ -match '\.(db|sqlite|sqlite3)$'
    })
    if ($forbidden.Count -gt 0) {
        throw "Generated or secret-bearing paths are tracked:`n$($forbidden -join "`n")"
    }

    git diff --check
    if ($LASTEXITCODE -ne 0) { throw "Git whitespace validation failed." }

    if (-not $SkipRemoteCheck) {
        $origin = git remote get-url origin
        $production = git remote get-url production
        if ($origin -notmatch 'CS-Ponkoj/Robotics-Programming-Lab-Staging(?:\.git)?$') {
            throw "origin must be the staging repository; found $origin"
        }
        if ($production -notmatch 'CS-Ponkoj/Robotics-Programming-Lab(?:\.git)?$') {
            throw "production must be the live repository; found $production"
        }
    }

    $sha = git rev-parse HEAD
    Write-Output "Release source check passed."
    Write-Output "Approved candidate SHA: $sha"
} finally {
    Pop-Location
}
