# NVIDIA global driver profile (same store the NVIDIA Control Panel uses)
$hw = Get-Hardware
if (-not $hw.nvidia) { Result -Status 'skipped' -Summary 'No NVIDIA GPU found'; return }
Import-OBNvDrs
$want = @(
  @{ id = 0x1057EB71; v = 1; label = 'Power management mode'; names = @{ '0' = 'Adaptive'; '1' = 'Prefer maximum performance'; '2' = 'Driver controlled'; '3' = 'Consistent performance'; '4' = 'Prefer minimum power'; '5' = 'Normal' }; def = 'Normal' },
  @{ id = 0x007BA09E; v = 1; label = 'Low Latency Mode'; names = @{ '0' = 'Off'; '1' = 'On' }; def = 'Off' },
  @{ id = 0x00CE2691; v = 20; label = 'Texture filtering quality'; names = @{ '4294967286' = 'High quality'; '0' = 'Quality'; '10' = 'Performance'; '20' = 'High performance' }; def = 'Quality' }
)
Step 'Writing NVIDIA global profile'
try {
  $res = [OBNvDrs]::Run([uint32[]]@($want | ForEach-Object { [uint32]$_.id }), [uint32[]]@($want | ForEach-Object { [uint32]$_.v }), $null)
} catch { Result -Status 'failed' -Summary "NVIDIA driver API: $($_.Exception.Message)"; return }
for ($i = 0; $i -lt $want.Count; $i++) {
  $p = $res[$i] -split '\|'
  $existed = $p[1] -eq '1'; $before = [uint32]$p[2]; $st = [int]$p[3]
  $w = $want[$i]
  if ($st -ne 0) { Warn "$($w.label): driver returned $st"; continue }
  Add-Backup @{ type = 'nvdrs'; key = "nvdrs|$($w.id)"; settingId = [uint32]$w.id; existed = $existed; value = $before }
  $bText = if ($existed) { $n = $w.names["$before"]; if ($n) { $n } else { "$before" } } else { $w.def }
  $aText = $w.names["$($w.v)"]
  if ($existed -and $before -eq [uint32]$w.v) { Same $w.label $aText } else { Change $w.label $bText $aText }
}
Result -Summary 'NVIDIA profile tuned for performance'
