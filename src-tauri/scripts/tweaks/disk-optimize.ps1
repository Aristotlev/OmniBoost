# TRIM SSDs, defrag HDDs only when needed
$vols = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter -and @('NTFS', 'ReFS') -contains "$($_.FileSystem)" })
$pds = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
$done = 0
foreach ($v in $vols) {
  if (Test-SkipRequested) { Info 'Stopped. Remaining drives were not optimized.'; break }
  $l = "$($v.DriveLetter)"
  $media = 'Unknown'
  try {
    $part = Get-Partition -DriveLetter $l -ErrorAction Stop | Select-Object -First 1
    $pd = $pds | Where-Object { "$($_.DeviceId)" -eq "$($part.DiskNumber)" } | Select-Object -First 1
    if ($pd) { $media = "$($pd.MediaType)"; if ($media -eq 'Unspecified' -and "$($pd.BusType)" -eq 'NVMe') { $media = 'SSD' } }
  } catch {}
  try {
    if ($media -eq 'SSD') {
      Step "Running TRIM on drive ${l}: (SSD)"
      Optimize-Volume -DriveLetter $l -ReTrim -ErrorAction Stop
      Change "Drive ${l}: (SSD)" 'Unused blocks pending' 'TRIM complete'
    } elseif ($media -eq 'HDD') {
      Step "Analyzing drive ${l}: (HDD)"
      $wv = Get-CimInstance Win32_Volume -Filter "DriveLetter='${l}:'"
      $an = Invoke-CimMethod -InputObject $wv -MethodName DefragAnalysis
      $pct = $an.DefragAnalysis.FilePercentFragmentation
      if ($an.DefragRecommended) {
        Step "Defragmenting drive ${l}: ($pct% fragmented). Hard drives can take a while"
        Optimize-Volume -DriveLetter $l -Defrag -ErrorAction Stop
        Change "Drive ${l}: (HDD)" "$pct% fragmented" 'Defragmented'
      } else { Same "Drive ${l}: (HDD)" "$pct% fragmented, no defrag needed" }
    } else {
      Step "Optimizing drive ${l}:"
      Optimize-Volume -DriveLetter $l -ErrorAction Stop
      Change "Drive ${l}:" 'Not optimized' 'Optimized'
    }
    $done++
  } catch { Warn "Drive ${l}: $($_.Exception.Message)" }
}
Result -Summary "$done drive(s) optimized"
