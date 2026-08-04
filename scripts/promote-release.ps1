param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$')]
    [string]$ReleaseTag,
    [switch]$ConfirmProduction
)

$ErrorActionPreference = "Stop"
if (-not $ConfirmProduction) {
    throw "Production promotion requires -ConfirmProduction. No remote was changed."
}

$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
Push-Location $repositoryRoot
try {
    & (Join-Path $PSScriptRoot "check-release.ps1")
    if ($LASTEXITCODE -ne 0) { throw "Release source check failed." }

    $branch = git branch --show-current
    if ($branch -ne "main") { throw "Production promotion is allowed only from staging main." }

    git fetch origin main
    git fetch production main
    $sha = git rev-parse HEAD
    $stagingSha = git rev-parse origin/main
    if ($sha -ne $stagingSha) {
        throw "Local HEAD does not match staging origin/main. Push and re-run SQA first."
    }
    git merge-base --is-ancestor production/main $sha
    if ($LASTEXITCODE -ne 0) {
        throw "Production main is not an ancestor of the approved staging commit. Refusing to force-push."
    }
    if (git rev-parse -q --verify "refs/tags/$ReleaseTag") {
        throw "Release tag $ReleaseTag already exists. Tags are immutable."
    }

    & (Join-Path $PSScriptRoot "verify-local.ps1") -ApiBaseUrl "https://robotics-programming-lab-api.onrender.com"
    if ($LASTEXITCODE -ne 0) { throw "Final SQA failed; production was not changed." }

    git tag -a $ReleaseTag $sha -m "Robotics Programming Lab $ReleaseTag"
    git push --atomic production "$sha`:refs/heads/main" "refs/tags/$ReleaseTag"
    if ($LASTEXITCODE -ne 0) {
        git tag -d $ReleaseTag | Out-Null
        throw "Atomic production promotion failed. The local release tag was removed."
    }

    git fetch production main
    $publishedSha = git rev-parse production/main
    if ($publishedSha -ne $sha) {
        throw "Production verification failed: expected $sha but found $publishedSha."
    }

    Write-Output "Production promotion completed."
    Write-Output "Release: $ReleaseTag"
    Write-Output "Commit:  $sha"
} finally {
    Pop-Location
}
