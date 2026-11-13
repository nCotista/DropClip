# Removes a per-user DropClip install (see install.ps1). Settings, the
# device identity and paired devices in %APPDATA% are kept, so a reinstall
# stays paired; delete that folder by hand to forget them.
$ErrorActionPreference = 'SilentlyContinue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe = Join-Path $dir 'dropclip_desktop.exe'

Add-Type -AssemblyName System.Windows.Forms
$ok = [System.Windows.Forms.MessageBox]::Show(
  'Remove DropClip from this PC?', 'Uninstall DropClip', 'YesNo', 'Question')
if ($ok -ne 'Yes') { exit 0 }

Get-Process dropclip_desktop | Where-Object { $_.Path -eq $exe } | Stop-Process -Force
Start-Sleep -Milliseconds 500
Remove-Item (Join-Path ([Environment]::GetFolderPath('Programs')) 'DropClip.lnk') -Force
Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'DropClip.lnk') -Force
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DropClip' -Recurse -Force
# "Start at login" from Settings, or it points at a deleted exe.
Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name DropClip

# This script lives in the folder it deletes: finish from a temp copy.
$cleanup = Join-Path $env:TEMP 'dropclip_uninstall_cleanup.cmd'
"@echo off`r`nping 127.0.0.1 -n 3 > nul`r`nrmdir /s /q `"$dir`"`r`ndel `"%~f0`"" |
  Set-Content $cleanup -Encoding ascii
Start-Process cmd.exe -ArgumentList "/c `"$cleanup`"" -WindowStyle Hidden
