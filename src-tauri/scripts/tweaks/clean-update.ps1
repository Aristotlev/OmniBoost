# Windows Update download cache and Delivery Optimization cache
$drive = Get-SysDriveLetter
$before = Get-DriveFree $drive
Step 'Clearing the Windows Update download cache'
$was = @{}
foreach ($s in @('wuauserv', 'bits')) {
  $x = Get-Service -Name $s -ErrorAction SilentlyContinue
  if ($x) { $was[$s] = "$($x.Status)"; Stop-Service -Name $s -Force -ErrorAction SilentlyContinue }
}
[void](Clear-Folder "$env:SystemRoot\SoftwareDistribution\Download" 0 'Windows Update downloads')
foreach ($s in @('wuauserv', 'bits')) { if ($was[$s] -eq 'Running') { Start-Service -Name $s -ErrorAction SilentlyContinue } }
Step 'Clearing the Delivery Optimization cache'
try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop | Out-Null; Info 'Delivery Optimization cache cleared' } catch {}
$after = Get-DriveFree $drive
$freed = [math]::Max(0, $after - $before)
Change "Free space on ${drive}:" (Format-Bytes $before) (Format-Bytes $after)
Result -Summary "Freed $(Format-Bytes $freed)" -Freed $freed
