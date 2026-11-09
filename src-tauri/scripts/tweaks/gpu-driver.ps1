# GPU driver age check with one-click update links
$hw = Get-Hardware
$manual = @(); $n = 0
foreach ($g in $hw.gpus) {
  $vendor = if ($g.Name -match '(?i)nvidia') { 'NVIDIA' } elseif ($g.Name -match '(?i)(amd|radeon)') { 'AMD' } elseif ($g.Name -match '(?i)intel') { 'Intel' } else { continue }
  $n++
  $ver = $g.DriverVersion
  if ($vendor -eq 'NVIDIA' -and $ver) { $d = ($ver -replace '\.', ''); if ($d.Length -ge 5) { $t = $d.Substring($d.Length - 5); $ver = $t.Substring(0, 3) + '.' + $t.Substring(3) } }
  $age = if ($g.DriverDate) { [int]((Get-Date) - $g.DriverDate).TotalDays } else { -1 }
  $label = "$($g.Name) driver"
  if ($age -ge 0 -and $age -le 90) { Same $label "$ver ($age days old, current)"; continue }
  $url = switch ($vendor) { 'NVIDIA' { 'https://www.nvidia.com/en-us/drivers/' } 'AMD' { 'https://www.amd.com/en/support/download/drivers.html' } default { 'https://www.intel.com/content/www/us/en/support/detect.html' } }
  Warn "$label $ver is $age days old"
  $manual += (Manual "Update $vendor driver" "$($g.Name) runs $ver from $age days ago. Install the latest Game Ready / Adrenalin driver, then run Boost again to re-apply GPU settings." $url)
}
if ($n -eq 0) { Result -Status 'skipped' -Summary 'No dedicated GPU driver found'; return }
if ($manual.Count -gt 0) { Result -Status 'manual' -Summary 'GPU driver update available' -Manual $manual } else { Result -Summary 'GPU drivers are current' }
