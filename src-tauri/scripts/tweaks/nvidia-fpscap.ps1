# NVIDIA frame rate cap at refresh rate minus 3 (for G-SYNC / FreeSync monitors)
$hw = Get-Hardware
if (-not $hw.nvidia) { Result -Status 'skipped' -Summary 'No NVIDIA GPU found'; return }
Import-OBDisplay
$hz = 0
foreach ($l in [OBDisplay]::List()) { $p = $l -split '\|'; if ($p[6] -eq '1') { $hz = [int]$p[4] } }
if ($hz -lt 60) { Result -Status 'skipped' -Summary 'Could not read the main monitor refresh rate'; return }
$cap = $hz - 3
Import-OBNvDrs
try { $res = [OBNvDrs]::Run([uint32[]]@(0x10835002), [uint32[]]@([uint32]$cap), $null) } catch { Result -Status 'failed' -Summary $_.Exception.Message; return }
$p = $res[0] -split '\|'
Add-Backup @{ type = 'nvdrs'; key = 'nvdrs|276058114'; settingId = [uint32]0x10835002; existed = ($p[1] -eq '1'); value = [uint32]$p[2] }
$b = if ($p[1] -eq '1' -and [int]$p[2] -gt 0) { "$($p[2]) FPS" } else { 'Off' }
Change 'Max frame rate' $b "$cap FPS"
Result -Summary "FPS capped at $cap for a ${hz} Hz monitor"
