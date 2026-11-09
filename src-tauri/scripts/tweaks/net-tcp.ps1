# Network commands for lower ping and stable frame pacing
$reboot = $false
Step 'Flushing DNS cache'
& ipconfig /flushdns | Out-Null
Change 'DNS resolver cache' 'Cached entries' 'Flushed'

try {
  $lvl = "$((Get-NetTCPSetting -SettingName Internet -ErrorAction Stop).AutoTuningLevelLocal)"
  if ($lvl -eq 'Normal') { Same 'TCP receive window auto-tuning' 'Normal' }
  else {
    Add-Backup @{ type = 'cmd'; key = 'cmd|autotuning'; label = 'TCP receive window auto-tuning'; revert = "netsh int tcp set global autotuninglevel=$($lvl.ToLower())" }
    & netsh int tcp set global autotuninglevel=normal | Out-Null
    Change 'TCP receive window auto-tuning' $lvl 'Normal'
  }
} catch {}

try {
  $rss = "$((Get-NetOffloadGlobalSetting -ErrorAction Stop).ReceiveSideScaling)"
  if ($rss -eq 'Enabled') { Same 'Receive Side Scaling (multi-core networking)' 'Enabled' }
  else {
    Add-Backup @{ type = 'cmd'; key = 'cmd|rss'; label = 'Receive Side Scaling'; revert = 'netsh int tcp set global rss=disabled' }
    & netsh int tcp set global rss=enabled | Out-Null
    Change 'Receive Side Scaling (multi-core networking)' $rss 'Enabled'
  }
} catch {}

$bcd = (& bcdedit /enum '{current}' 2>$null) -join "`n"
if ($bcd -match '(?im)^useplatformclock\s+(\S+)') {
  Add-Backup @{ type = 'cmd'; key = 'cmd|hpet'; label = 'Forced HPET timer'; revert = 'bcdedit /set {current} useplatformclock true'; reboot = $true }
  & bcdedit /deletevalue '{current}' useplatformclock | Out-Null
  Change 'Forced HPET timer (bcdedit useplatformclock)' $Matches[1] 'Removed (Windows default)'
  $reboot = $true
} else { Same 'Forced HPET timer (bcdedit useplatformclock)' 'Not forced (Windows default)' }
Result -Summary 'Network stack tuned' -Reboot $reboot
