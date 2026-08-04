param(
    [string]$ApiBaseUrl = "https://api.example.test"
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$source = Join-Path $repositoryRoot "frontend"
$safeRoot = Join-Path $env:LOCALAPPDATA "RoboticsLabFlutterSqa"
$runName = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$target = Join-Path $safeRoot $runName

$resolvedSafeRoot = [System.IO.Path]::GetFullPath($safeRoot)
$resolvedTarget = [System.IO.Path]::GetFullPath($target)
if (-not $resolvedTarget.StartsWith($resolvedSafeRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to create the temporary verification copy outside LOCALAPPDATA."
}

New-Item -ItemType Directory -Force -Path $target | Out-Null
foreach ($directory in @("fonts", "lib", "test", "web")) {
    Copy-Item -LiteralPath (Join-Path $source $directory) -Destination $target -Recurse
}
foreach ($file in @(".metadata", "analysis_options.yaml", "pubspec.lock", "pubspec.yaml")) {
    Copy-Item -LiteralPath (Join-Path $source $file) -Destination $target
}

Push-Location $target
try {
    flutter pub get
    flutter analyze
    flutter test
    flutter build web --release --dart-define="API_BASE_URL=$ApiBaseUrl"
} finally {
    Pop-Location
}

Write-Output "OneDrive-safe Flutter verification passed."
Write-Output "Temporary artifact: $target"
