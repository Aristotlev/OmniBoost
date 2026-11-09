# Windows Disk Cleanup (cleanmgr) on a safe, fast set of categories.
# Windows Update Cleanup is left out: it is the slow part of cleanmgr and the
# optional "Deep clean the component store" step does the same work with live progress.
$handlers = @('Active Setup Temp Folders', 'Downloaded Program Files', 'Internet Cache Files', 'Old ChkDsk Files', 'Setup Log Files',
  'System error memory dump files', 'Temporary Files', 'Temporary Setup Files', 'Thumbnail Cache', 'Windows Error Reporting Files',
  'Windows Upgrade Log Files', 'Diagnostic Data Viewer database files', 'Feedback Hub Archive log files', 'Windows Defender',
  'RetailDemo Offline Content', 'Upgrade Discarded Files', 'Offline Pages Files', 'Memory Dump Files')
$base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
$n = 0
# Select our categories and clear every other one (older builds also selected Windows Update Cleanup).
foreach ($k in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
  $on = $handlers -contains $k.PSChildName
  $v = 0; if ($on) { $v = 2; $n++ }
  New-ItemProperty -LiteralPath $k.PSPath -Name 'StateFlags0777' -Value $v -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
}
Info "Disk Cleanup will clear $n categories. Previous Windows installs, the Recycle Bin and shader caches are kept."
$drive = Get-SysDriveLetter
$before = Get-DriveFree $drive
$max = 6
$p = Start-Process -FilePath "$env:SystemRoot\System32\cleanmgr.exe" -ArgumentList '/sagerun:777' -PassThru -WindowStyle Hidden
$t0 = Get-Date
$how = 'done'
Step 'Running Windows Disk Cleanup'
while (-not $p.HasExited) {
  Start-Sleep -Seconds 2
  $el = (Get-Date) - $t0
  $so = [math]::Max(0, (Get-DriveFree $drive) - $before)
  Step ('Running Windows Disk Cleanup, {0}, {1} freed so far' -f (Format-Elapsed $el), (Format-Bytes $so))
  if (Test-SkipRequested) { $how = 'skipped'; break }
  if ($el.TotalMinutes -ge $max) { $how = 'timeout'; break }
}
if (-not $p.HasExited) { Stop-ProcessTree $p.Id; Start-Sleep -Seconds 1 }
if ($how -eq 'skipped') { Info 'Disk Cleanup stopped. Space freed so far is kept.' }
if ($how -eq 'timeout') { Info "Disk Cleanup stopped after $max minutes. Space freed so far is kept." }
$after = Get-DriveFree $drive
$freed = [math]::Max(0, $after - $before)
Change "Free space on ${drive}:" (Format-Bytes $before) (Format-Bytes $after)
$status = if ($how -eq 'skipped') { 'skipped' } else { 'done' }
$sum = if ($how -eq 'done') { "Freed $(Format-Bytes $freed)" } else { "Stopped early, freed $(Format-Bytes $freed)" }
Result -Status $status -Summary $sum -Freed $freed
