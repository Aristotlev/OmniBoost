# Drive health (SMART) and file system scan
$reboot = $false
Step 'Reading drive health (SMART)'
foreach ($pd in @(Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
  $rel = $null; try { $rel = $pd | Get-StorageReliabilityCounter -ErrorAction Stop } catch {}
  $bits = @("$($pd.HealthStatus)")
  if ($rel -and $rel.Wear -ne $null) { $bits += "$($rel.Wear)% wear" }
  if ($rel -and $rel.Temperature) { $bits += "$($rel.Temperature) C" }
  if ("$($pd.HealthStatus)" -eq 'Healthy') { Same "$($pd.FriendlyName) health" ($bits -join ', ') } else { Warn "$($pd.FriendlyName): $($bits -join ', '). Back up your data." }
}
$vols = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter -and @('NTFS', 'ReFS') -contains "$($_.FileSystem)" })
$sys = $env:SystemDrive.TrimEnd(':')
$issues = 0
foreach ($v in $vols) {
  if (Test-SkipRequested) { Info 'Stopped. Remaining drives were not scanned.'; break }
  $l = "$($v.DriveLetter)"
  Step "Scanning drive ${l}: for file system errors"
  try {
    $r = "$(Repair-Volume -DriveLetter $l -Scan -ErrorAction Stop)"
    if ($r -eq 'NoErrorsFound') { Same "Drive ${l}: file system" 'No errors' ; continue }
    $issues++
    if ($l -eq $sys) {
      $f = "$(Repair-Volume -DriveLetter $l -OfflineScanAndFix -ErrorAction Stop)"
      Change "Drive ${l}: file system" $r 'Repair runs at next restart'
      $reboot = $true
    } else {
      $f = "$(Repair-Volume -DriveLetter $l -SpotFix -ErrorAction Stop)"
      Change "Drive ${l}: file system" $r "Repaired ($f)"
    }
  } catch { Warn "Drive ${l}: $($_.Exception.Message)" }
}
$sum = if ($issues -eq 0) { "$($vols.Count) drives scanned, no errors" } else { "$issues drive(s) had errors and were repaired" }
Result -Summary $sum -Reboot $reboot
