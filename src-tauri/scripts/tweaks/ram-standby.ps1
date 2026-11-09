# Free standby memory so games get clean RAM
Import-OBMem
function MemNow { $m = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory; return @{ free = [long]$m.FreeAndZeroPageListBytes; standby = [long]$m.StandbyCacheCoreBytes + [long]$m.StandbyCacheNormalPriorityBytes + [long]$m.StandbyCacheReserveBytes } }
$b = MemNow
Step 'Purging the standby list'
$r = [OBMem]::PurgeStandby()
Start-Sleep -Milliseconds 700
$a = MemNow
if ($r -ne 0) { Result -Status 'failed' -Summary "Windows refused the purge (status $r)"; return }
Change 'Standby cache' (Format-Bytes $b.standby) (Format-Bytes $a.standby)
Change 'Free RAM' (Format-Bytes $b.free) (Format-Bytes $a.free)
Result -Summary "Freed $(Format-Bytes ([math]::Max(0, $a.free - $b.free))) of RAM"
