# Builds the Windows release and packs it as 3.x did (X01.3):
#   PureLive-<version>-<build>-windows-x64-portable.zip  (data in UserData beside the exe)
#   PureLive-<version>-<build>-windows-x64-setup.exe     (pinned Inno Setup, same AppId as 3.x)
# Run on the Windows host from the repository root: pwsh tools\release\package_windows.ps1 [outDir]
param([string]$Out = "$PSScriptRoot\..\..\build\release", [string]$Iscc = $env:PURELIVE_ISCC)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path "$PSScriptRoot\..\.."
$flutter = if ($env:FLUTTER) { $env:FLUTTER } else { 'flutter' }
if (-not $Iscc) {
  $Iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe", "$env:ProgramFiles\Inno Setup 7\ISCC.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $Iscc -or -not (Test-Path -LiteralPath $Iscc)) { throw 'Pinned Inno Setup is missing; set PURELIVE_ISCC or pass -Iscc.' }
$toolchain = @{}
Get-Content -LiteralPath "$root\toolchain.env" | ForEach-Object { if ($_ -match '^([A-Z_]+)=(.+)$') { $toolchain[$Matches[1]] = $Matches[2] } }
# Resolve NuGet before configuring native WebView dependencies; a stale CMake
# cache must not hide a missing command on a fresh toolchain.
$nuget = Get-Command nuget.exe -ErrorAction SilentlyContinue
if (-not $nuget) { throw 'Pinned NuGet is missing; add its directory to PATH.' }
$nugetVersion = [Reflection.AssemblyName]::GetAssemblyName($nuget.Source).Version
if ("$($nugetVersion.Major).$($nugetVersion.Minor).$($nugetVersion.Build)" -ne $toolchain.NUGET_VERSION) {
  throw 'NuGet does not match toolchain.env'
}
# ISCC intentionally has no useful PE file version; ask its preprocessor.
& $Iscc /Q "/DExpectedInnoVersion=$($toolchain.INNO_SETUP_VERSION)" "$root\tools\toolchain\inno-version.iss"
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup does not match toolchain.env' }
$pubspec = Get-Content "$root\apps\pure_live\pubspec.yaml" | Select-String '^version: ([0-9.]+)\+([0-9]+)$'
$version = $pubspec.Matches[0].Groups[1].Value; $build = $pubspec.Matches[0].Groups[2].Value
$name = "PureLive-$version-$build-windows-x64"
New-Item -ItemType Directory -Force $Out | Out-Null
$Out = Resolve-Path $Out
& pwsh -NoProfile -File "$root\tools\ffmpeg_kit\fetch.ps1" windows | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Windows FFmpeg preparation failed' }
Push-Location "$root\apps\pure_live"
try {
  & $flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }
} finally { Pop-Location }
$release = "$root\apps\pure_live\build\windows\x64\runner\Release"
# A clean copy: no UserData or logs from a test run.
$stage = Join-Path ([IO.Path]::GetTempPath()) ("$name-portable-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
Get-ChildItem -LiteralPath $release -Force | Where-Object { $_.Name -ne 'UserData' -and $_.Extension -ne '.log' } | Copy-Item -Destination $stage -Recurse
Compress-Archive -Path "$stage\*" -DestinationPath "$Out\$name-portable.zip" -Force
& $Iscc "/DSourceDir=$stage" "/DAppVersion=$version" "/DArtifactVersion=$version-$build" "/DOutputDir=$Out" "$root\apps\pure_live\windows\packaging\exe\pure_live.iss" | Select-Object -Last 3
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup packaging failed' }
Get-ChildItem $Out -Filter "$name*" | ForEach-Object { "$($_.Name) $($_.Length)" }
