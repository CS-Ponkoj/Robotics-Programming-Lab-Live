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

    # Include non-ignored new files so this check is useful before the files are
    # staged as well as after they are committed.
    $tracked = @(git ls-files --cached --others --exclude-standard)
    $forbidden = @($tracked | Where-Object {
        $_ -match '(^|/)(\.env|env|venv|venvs|build|\.dart_tool|\.local-run)(/|$)' -or
        $_ -match '\.(db|sqlite|sqlite3|dump)$'
    })
    if ($forbidden.Count -gt 0) {
        throw "Generated or secret-bearing paths are tracked:`n$($forbidden -join "`n")"
    }

    $requiredCloneFiles = @(
        ".python-version",
        "README.md",
        "AGENTS.md",
        "docker-compose.yml",
        "backend/.env.example",
        "backend/requirements.txt",
        "backend/alembic.ini",
        "backend/Dockerfile.sandbox",
        "backend/Dockerfile.ros2",
        "backend/tests/test_config.py",
        "frontend/pubspec.yaml",
        "frontend/pubspec.lock",
        "scripts/setup-local.ps1",
        "scripts/create-local-handoff-package.ps1",
        "scripts/run-local.ps1",
        "scripts/backup-local-database.ps1",
        "scripts/stop-local.ps1",
        "scripts/local-environment.psm1",
        "scripts/local-database.psm1",
        "scripts/verify-local.ps1",
        "scripts/verify-local-layout.ps1",
        "scripts/verify-local-handoff-package.ps1",
        "scripts/verify-portable-clone.ps1",
        "scripts/setup-local.sh",
        "scripts/create-local-handoff-package.sh",
        "scripts/run-local.sh",
        "scripts/backup-local-database.sh",
        "scripts/stop-local.sh",
        "scripts/check-ros2-local.sh",
        "scripts/linux-local-common.sh",
        "scripts/linux-local-database.sh",
        "scripts/verify-linux-database-handoff.sh",
        "scripts/verify-local.sh",
        "local_handoff_package/.gitignore",
        "local_handoff_package/README.md",
        "docs/guides/FIRST_TIME_RUN.md",
        "docs/guides/FIRST_TIME_RUN_WINDOWS.md",
        "docs/guides/FIRST_TIME_RUN_UBUNTU.md"
    )
    $missingCloneFiles = @($requiredCloneFiles | Where-Object { $_ -notin $tracked })
    if ($missingCloneFiles.Count -gt 0) {
        throw "A fresh clone would be missing required project files:`n$($missingCloneFiles -join "`n")"
    }

    $assignmentFiles = @($tracked | Where-Object {
        $_ -match '^backend/assignments/assignment_[1-6]\.json$'
    })
    if ($assignmentFiles.Count -ne 6) {
        throw "A fresh clone must contain exactly the six current assignment JSON files; found $($assignmentFiles.Count)."
    }
    foreach ($assignmentFile in $assignmentFiles) {
        $assignment = Get-Content -LiteralPath (Join-Path $repositoryRoot $assignmentFile) -Raw |
            ConvertFrom-Json
        if (-not [string]::IsNullOrWhiteSpace($assignment.reference_solution_path)) {
            $solutionPath = $assignment.reference_solution_path -replace '\\', '/'
            if ($solutionPath -notin $tracked) {
                throw "$assignmentFile references a solution file that a fresh clone would not contain: $solutionPath"
            }
        }
    }

    $migrationFiles = @($tracked | Where-Object {
        $_ -match '^backend/migrations/versions/[^/]+\.py$'
    })
    if ($migrationFiles.Count -lt 3) {
        throw "A fresh clone is missing one or more required database migrations."
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
    Write-Output "Fresh-clone completeness check passed for setup, six assignments, solutions, and migrations."
    Write-Output "Approved candidate SHA: $sha"
} finally {
    Pop-Location
}
