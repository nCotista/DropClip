# Packs the Release build into DropClip-Setup-<version>.exe with IExpress
# (built into Windows, no extra tools). Run after:
#   flutter build windows --release
# Output: apps/desktop/build/installer/DropClip-Setup-<version>.exe
$ErrorActionPreference = 'Stop'
$desktop = Split-Path -Parent $PSScriptRoot
$release = Join-Path $desktop 'build\windows\x64\runner\Release'
$out = Join-Path $desktop 'build\installer'
$stage = Join-Path $out 'stage'
if (-not (Test-Path (Join-Path $release 'dropclip_desktop.exe'))) {
  throw "No Release build at $release; run 'flutter build windows --release' first."
}
$version = ((Select-String -Path (Join-Path $desktop 'pubspec.yaml') -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value) -replace '\+.*$', ''

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null

# The app plus the MSVC runtime it links against, so PCs without the
# Visual C++ Redistributable can run it (app-local deployment).
$app = Join-Path $stage 'app'
Copy-Item $release $app -Recurse
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  Copy-Item (Join-Path "$env:WINDIR\System32" $dll) $app -Force
}
Compress-Archive -Path "$app\*" -DestinationPath (Join-Path $stage 'DropClip.zip') -CompressionLevel Optimal
Remove-Item $app -Recurse -Force
Copy-Item (Join-Path $PSScriptRoot 'install.ps1'), (Join-Path $PSScriptRoot 'uninstall.ps1') $stage
Set-Content (Join-Path $stage 'version.txt') $version -Encoding ascii

$exe = Join-Path $out "DropClip-Setup-$version.exe"
$files = 'DropClip.zip', 'install.ps1', 'uninstall.ps1', 'version.txt'
$sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=0
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=DropClip is installed and running. Find it in the Start menu or on your desktop.
TargetName=$exe
FriendlyName=DropClip Setup
AppLaunched=powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File install.ps1
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
SourceFiles=SourceFiles
[Strings]
$(($files | ForEach-Object -Begin { $i = 0 } -Process { "FILE$i=`"$_`""; $i++ }) -join "`r`n")
[SourceFiles]
SourceFiles0=$stage\
[SourceFiles0]
$(($files | ForEach-Object -Begin { $i = 0 } -Process { "%FILE$i%="; $i++ }) -join "`r`n")
"@
$sedPath = Join-Path $out 'DropClip.sed'
Set-Content $sedPath $sed -Encoding ascii
if (Test-Path $exe) { Remove-Item $exe -Force }
Start-Process "$env:WINDIR\System32\iexpress.exe" -ArgumentList '/N', '/Q', $sedPath -Wait
if (-not (Test-Path $exe)) { throw 'IExpress did not produce the installer.' }
Get-Item $exe | Select-Object FullName, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } }
