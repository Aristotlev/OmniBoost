# Highest refresh rate every monitor supports at its current resolution
Import-OBDisplay
$changed = 0; $n = 0
foreach ($l in [OBDisplay]::List()) {
  $p = $l -split '\|'
  $dev = $p[0]; $name = $p[1]; $cur = [int]$p[4]; $max = [int]$p[5]
  $n++
  $label = "$name ($($p[2])x$($p[3])) refresh rate"
  if ($max -le $cur) { Same $label "$cur Hz (max)"; continue }
  Step "Switching $name to $max Hz"
  Add-Backup @{ type = 'display'; key = "display|$dev"; device = $dev; name = $name; hz = $cur; newHz = $max }
  $r = [OBDisplay]::SetFrequency($dev, $max)
  if ($r -eq 0) { Change $label "$cur Hz" "$max Hz"; $changed++ } else { Warn "$name did not accept $max Hz (code $r)" }
}
if ($n -eq 0) { Result -Status 'skipped' -Summary 'No active displays found'; return }
Result -Summary $(if ($changed -gt 0) { "$changed display(s) switched to max refresh rate" } else { 'All displays already at max refresh rate' })
