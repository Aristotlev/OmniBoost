# Empty the Recycle Bin on all drives
$drives = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } | ForEach-Object { "$($_.DriveLetter)" })
$before = 0; foreach ($d in $drives) { $before += Get-DriveFree $d }
Step 'Emptying the Recycle Bin'
try { Clear-RecycleBin -Force -ErrorAction Stop } catch {}
$after = 0; foreach ($d in $drives) { $after += Get-DriveFree $d }
$freed = [math]::Max(0, $after - $before)
if ($freed -gt 0) { Change 'Recycle Bin' (Format-Bytes $freed) 'empty' } else { Same 'Recycle Bin' 'already empty' }
Result -Summary "Freed $(Format-Bytes $freed)" -Freed $freed
