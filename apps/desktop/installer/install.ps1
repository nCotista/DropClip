# DropClip per-user installer. Runs from the self-extracting setup exe
# (see build_installer.ps1): no admin rights, installs to
# %LOCALAPPDATA%\Programs\DropClip, adds Start menu + desktop shortcuts and
# an "Apps & features" entry, then starts DropClip.
param(
  [string]$Target = (Join-Path $env:LOCALAPPDATA 'Programs\DropClip'),
  [switch]$NoShortcuts,
  [switch]$NoLaunch
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$zip = Join-Path $here 'DropClip.zip'
$exe = Join-Path $Target 'dropclip_desktop.exe'

try {
  # An update: close the running copy so its files can be replaced.
  Get-Process dropclip_desktop -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $exe } | Stop-Process -Force
  Start-Sleep -Milliseconds 500

  # Extract beside the target and prove the package is complete before
  # touching the old install: a truncated zip or a full disk must not leave
  # the user with no working DropClip at all.
  $parent = Split-Path -Parent $Target
  $leaf = Split-Path -Leaf $Target
  $stage = Join-Path $parent "$leaf.new"
  $backup = Join-Path $parent "$leaf.old"
  if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
  New-Item -ItemType Directory -Force $stage | Out-Null
  Expand-Archive -Path $zip -DestinationPath $stage -Force
  if (-not (Test-Path (Join-Path $stage 'dropclip_desktop.exe'))) {
    throw 'The update package is incomplete (dropclip_desktop.exe is missing).'
  }
  Copy-Item (Join-Path $here 'uninstall.ps1') $stage -Force

  if (Test-Path $backup) { Remove-Item $backup -Recurse -Force }
  if (Test-Path $Target) { Rename-Item -LiteralPath $Target -NewName "$leaf.old" }
  try {
    Rename-Item -LiteralPath $stage -NewName $leaf
  } catch {
    # Put the old version back so the shortcut still works.
    if (Test-Path $backup) { Rename-Item -LiteralPath $backup -NewName $leaf }
    throw
  }
  # The new version is live; an AV lock on the backup is not fatal.
  if (Test-Path $backup) { try { Remove-Item $backup -Recurse -Force } catch { } }

  if (-not $NoShortcuts) {
    $shell = New-Object -ComObject WScript.Shell
    $links = @(
      (Join-Path ([Environment]::GetFolderPath('Programs')) 'DropClip.lnk'),
      (Join-Path ([Environment]::GetFolderPath('Desktop')) 'DropClip.lnk')
    )
    foreach ($l in $links) {
      $s = $shell.CreateShortcut($l)
      $s.TargetPath = $exe
      $s.WorkingDirectory = $Target
      $s.IconLocation = "$exe,0"
      $s.Description = 'DropClip - clipboard and file sync on your Wi-Fi'
      $s.Save()
    }

    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DropClip'
    New-Item -Path $key -Force | Out-Null
    $uninstall = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Target\uninstall.ps1`""
    $version = (Get-Content (Join-Path $here 'version.txt') -ErrorAction SilentlyContinue)
    $props = @{
      DisplayName     = 'DropClip'
      DisplayVersion  = "$version"
      Publisher       = 'DropClip'
      DisplayIcon     = "$exe,0"
      InstallLocation = $Target
      UninstallString = $uninstall
      NoModify        = 1
      NoRepair        = 1
    }
    foreach ($p in $props.GetEnumerator()) {
      $type = if ($p.Value -is [int]) { 'DWord' } else { 'String' }
      New-ItemProperty -Path $key -Name $p.Key -Value $p.Value -PropertyType $type -Force | Out-Null
    }
    $size = (Get-ChildItem $Target -Recurse | Measure-Object Length -Sum).Sum / 1KB
    New-ItemProperty -Path $key -Name EstimatedSize -Value ([int]$size) -PropertyType DWord -Force | Out-Null
  }

  if (-not $NoLaunch) { Start-Process $exe -WorkingDirectory $Target }
} catch {
  Add-Type -AssemblyName System.Windows.Forms
  [System.Windows.Forms.MessageBox]::Show(
    "DropClip could not be installed:`n`n$($_.Exception.Message)",
    'DropClip Setup', 'OK', 'Error') | Out-Null
  exit 1
}
