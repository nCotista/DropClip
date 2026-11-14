# Removes a per-user DropClip install (see install.ps1). Settings, the
# device identity and paired devices in %APPDATA% are kept, so a reinstall
# stays paired; delete that folder by hand to forget them.
#
# -Silent skips the confirmation dialog (used by the installer smoke test).
param([switch]$Silent)
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $dir 'dropclip_desktop.exe'
$uninstallKey = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\DropClip'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

if (-not $Silent) {
  Add-Type -AssemblyName System.Windows.Forms
  $ok = [System.Windows.Forms.MessageBox]::Show(
    'Remove DropClip from this PC?', 'Uninstall DropClip', 'YesNo', 'Question')
  if ($ok -ne 'Yes') { exit 0 }
}

# Stop the tray app. Match the install path first; when a process's path
# cannot be read (an elevated copy, or one started from an old install
# path), fall back to the image name. Leaving it running used to lock the
# folder: the files stayed, but the "Apps & features" entry was already
# gone, so the uninstall could not be retried.
foreach ($p in @(Get-Process dropclip_desktop -ErrorAction SilentlyContinue)) {
  $path = $null
  try { $path = $p.Path } catch { }
  if ($null -eq $path -or $path -eq $exe) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  }
}
$deadline = (Get-Date).AddSeconds(10)
while ((Get-Date) -lt $deadline -and
    (Get-Process dropclip_desktop -ErrorAction SilentlyContinue)) {
  Start-Sleep -Milliseconds 250
}
if (Get-Process dropclip_desktop -ErrorAction SilentlyContinue) {
  # An elevated copy cannot be stopped from here; keep the install intact
  # and retryable instead of leaving a half-deleted folder behind.
  if (-not $Silent) {
    [System.Windows.Forms.MessageBox]::Show(
      'DropClip is still running. Quit it from the tray, then uninstall again.',
      'Uninstall DropClip', 'OK', 'Warning') | Out-Null
  }
  exit 1
}

foreach ($link in @(
    (Join-Path ([Environment]::GetFolderPath('Programs')) 'DropClip.lnk'),
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'DropClip.lnk'))) {
  Remove-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
}
# "Start at login" from Settings, or it points at a deleted exe.
Remove-ItemProperty -Path $runKey -Name DropClip -ErrorAction SilentlyContinue

# A failed update can leave DropClip.new / DropClip.old beside the install.
foreach ($stale in @("$dir.new", "$dir.old")) {
  if (Test-Path -LiteralPath $stale) {
    Remove-Item -LiteralPath $stale -Recurse -Force -ErrorAction SilentlyContinue
  }
}

# This script lives in the folder it deletes, so the delete runs from a temp
# helper after PowerShell exits. The helper retries (an antivirus scan can
# hold a file), removes the "Apps & features" entry only once the folder is
# really gone, and logs what happened: a failed uninstall stays retryable.
$log = Join-Path $env:TEMP 'dropclip-uninstall.log'
$helper = Join-Path $env:TEMP "dropclip-uninstall-$([guid]::NewGuid().ToString('N')).cmd"
$lines = @(
  '@echo off',
  'cd /d "%TEMP%"',
  "set log=$log",
  'echo %DATE% %TIME% removing DropClip > "%log%"',
  'set /a tries=0',
  ':retry',
  'set /a tries+=1',
  "rmdir /s /q `"$dir`" >> `"%log%`" 2>&1",
  "if exist `"$dir`" if %tries% lss 20 (",
  '  ping 127.0.0.1 -n 2 >nul',
  '  goto retry',
  ')',
  "if exist `"$dir`" goto failed",
  "reg delete `"$uninstallKey`" /f >> `"%log%`" 2>&1",
  'echo OK >> "%log%"',
  'goto done',
  ':failed',
  "echo FAILED: `"$dir`" is still there >> `"%log%`"",
  ':done',
  'del "%~f0"'
)
Set-Content -LiteralPath $helper -Value ($lines -join "`r`n") -Encoding ascii -NoNewline
Start-Process -FilePath cmd.exe -ArgumentList "/c `"$helper`"" -WindowStyle Hidden
