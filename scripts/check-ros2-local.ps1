param([switch]$Build)

$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$image = 'robotics-lab-ros2-grader:jazzy-v1'

$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
    $installedDocker = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
    if (Test-Path -LiteralPath $installedDocker) {
        $docker = Get-Item -LiteralPath $installedDocker
    }
}
if (-not $docker) {
    throw 'Docker Desktop is not installed or docker is not on PATH. Install and start Docker Desktop with Linux containers, then run this check again.'
}
$dockerExecutable = if ($docker.Source) { $docker.Source } else { $docker.FullName }

& $dockerExecutable info | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Docker Desktop is installed but its Linux engine is not running.'
}

if ($Build) {
    Push-Location $repositoryRoot
    try {
        & $dockerExecutable compose --profile build build ros2-grader-image
        if ($LASTEXITCODE -ne 0) { throw 'The ROS 2 grader image build failed.' }
    } finally {
        Pop-Location
    }
}

& $dockerExecutable image inspect $image | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'ROS 2 grader image is missing. Run: .\scripts\check-ros2-local.ps1 -Build'
}

Write-Output ('ROS 2 local grader is ready: ' + $image)
