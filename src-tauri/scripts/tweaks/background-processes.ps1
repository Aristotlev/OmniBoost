# Non-essential background processes: stop them now and keep them from starting again.
# Only processes on this list are touched, and never one that has an open window.
$rules = @(
  @{ n = 'YourPhone'; l = 'Phone Link' },
  @{ n = 'YourPhoneServer'; l = 'Phone Link server' },
  @{ n = 'PhoneExperienceHost'; l = 'Phone Link host' },
  @{ n = 'SkypeApp'; l = 'Skype (Store app)' },
  @{ n = 'SkypeBackgroundHost'; l = 'Skype background host' },
  @{ n = 'HxTsr'; l = 'Mail and Calendar sync' },
  @{ n = 'Video.UI'; l = 'Movies & TV' },
  @{ n = 'Music.UI'; l = 'Groove Music' },
  @{ n = 'Microsoft.Photos'; l = 'Photos (background)' },
  @{ n = 'SystemSettings'; l = 'Settings app (suspended)' },
  @{ n = 'GameBar'; l = 'Xbox Game Bar' },
  @{ n = 'GameBarFTServer'; l = 'Xbox Game Bar server' },
  @{ n = 'Cortana'; l = 'Cortana' },
  @{ n = 'Widgets'; l = 'Widgets' },
  @{ n = 'WidgetService'; l = 'Widgets service' },
  @{ n = 'CompatTelRunner'; l = 'Microsoft Compatibility Telemetry' },
  @{ n = 'GoogleUpdate'; l = 'Google Update' },
  @{ n = 'MicrosoftEdgeUpdate'; l = 'Microsoft Edge Update' },
  @{ n = 'BraveUpdate'; l = 'Brave Update' },
  @{ n = 'opera_autoupdate'; l = 'Opera auto-update' },
  @{ n = 'jusched'; l = 'Java Update Scheduler' },
  @{ n = 'AdobeARM'; l = 'Adobe Reader updater' },
  @{ n = 'AdobeIPCBroker'; l = 'Adobe IPC Broker' },
  @{ n = 'CCXProcess'; l = 'Adobe Creative Cloud Experience' },
  @{ n = 'CCLibrary'; l = 'Adobe Creative Cloud Libraries' },
  @{ n = 'AdobeCollabSync'; l = 'Adobe Acrobat sync' },
  @{ n = 'AdobeNotificationClient'; l = 'Adobe notifications' },
  @{ n = 'EpicWebHelper'; l = 'Epic Games web helper' },
  @{ n = 'CCleaner64'; l = 'CCleaner background monitoring' },
  @{ n = 'msedge'; l = 'Microsoft Edge (no window open)'; all = $true },
  @{ n = 'chrome'; l = 'Google Chrome (no window open)'; all = $true }
)
$stopped = 0; $freedRam = [long]0
Step 'Checking running processes'
foreach ($r in $rules) {
  $procs = @(Get-Process -Name $r.n -ErrorAction SilentlyContinue)
  if ($procs.Count -eq 0) { continue }
  # Browsers: only when none of their processes has a window. Everything else: per process.
  if ($r.all -and @($procs | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }).Count -gt 0) { continue }
  $targets = @($procs | Where-Object { $r.all -or $_.MainWindowHandle -eq [IntPtr]::Zero })
  if ($targets.Count -eq 0) { continue }
  $ram = [long](($targets | Measure-Object -Property WorkingSet64 -Sum).Sum)
  $ok = 0
  foreach ($p in $targets) { try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; $ok++ } catch {} }
  if ($ok -gt 0) {
    $stopped += $ok; $freedRam += $ram
    $what = if ($ok -gt 1) { "$ok processes, $(Format-Bytes $ram)" } else { "Running, $(Format-Bytes $ram)" }
    Change "$($r.l) ($($r.n).exe)" $what 'Stopped'
  }
}

# Third-party updater services: Manual. Updates still run through their scheduled tasks.
$svcs = @(
  @{ n = 'gupdate'; l = 'Google Update service' },
  @{ n = 'edgeupdate'; l = 'Microsoft Edge Update service' },
  @{ n = 'AdobeARMservice'; l = 'Adobe Acrobat Update service' },
  @{ n = 'AGSService'; l = 'Adobe Genuine Software service' },
  @{ n = 'AGMService'; l = 'Adobe Genuine Monitor service' }
)
$svcN = 0
foreach ($s in $svcs) {
  $w = Get-CimInstance Win32_Service -Filter "Name='$($s.n)'" -ErrorAction SilentlyContinue
  if (-not $w) { continue }
  if ($w.StartMode -eq 'Manual' -or $w.StartMode -eq 'Disabled') { Same $s.l $w.StartMode; continue }
  $delayed = Get-RegInfo "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.n)" 'DelayedAutostart'
  Add-Backup @{ type = 'service'; key = "service|$($s.n)"; name = $s.n; startMode = $w.StartMode; delayed = [bool]($delayed.existed -and $delayed.value -eq 1) }
  try {
    Set-Service -Name $s.n -StartupType Manual -ErrorAction Stop
    if ($w.State -eq 'Running') { Stop-Service -Name $s.n -Force -ErrorAction SilentlyContinue }
    Change $s.l $w.StartMode 'Manual (stopped)'
    $svcN++
  } catch { Warn "$($s.l): $($_.Exception.Message)" }
}

# Windows telemetry tasks that wake the PC up in the background.
$tasks = @(
  @{ p = '\Microsoft\Windows\Application Experience\'; n = 'Microsoft Compatibility Appraiser' },
  @{ p = '\Microsoft\Windows\Application Experience\'; n = 'ProgramDataUpdater' },
  @{ p = '\Microsoft\Windows\Customer Experience Improvement Program\'; n = 'Consolidator' },
  @{ p = '\Microsoft\Windows\Customer Experience Improvement Program\'; n = 'UsbCeip' },
  @{ p = '\Microsoft\Windows\Autochk\'; n = 'Proxy' },
  @{ p = '\Microsoft\Windows\DiskDiagnostic\'; n = 'Microsoft-Windows-DiskDiagnosticDataCollector' },
  @{ p = '\Microsoft\Windows\Feedback\Siuf\'; n = 'DmClient' },
  @{ p = '\Microsoft\Windows\Feedback\Siuf\'; n = 'DmClientOnScenarioDownload' },
  @{ p = '\Microsoft\Windows\Windows Error Reporting\'; n = 'QueueReporting' }
)
$taskN = 0
foreach ($t in $tasks) {
  $st = Get-ScheduledTask -TaskPath $t.p -TaskName $t.n -ErrorAction SilentlyContinue
  if (-not $st) { continue }
  $label = "Telemetry task: $($t.n)"
  if ("$($st.State)" -eq 'Disabled') { Same $label 'Disabled'; continue }
  Add-Backup @{ type = 'task'; key = "task|$($t.p)$($t.n)"; taskPath = $t.p; taskName = $t.n }
  try {
    Disable-ScheduledTask -TaskPath $t.p -TaskName $t.n -ErrorAction Stop | Out-Null
    Change $label "$($st.State)" 'Disabled'
    $taskN++
  } catch { Info "$label is protected by Windows and was left on" }
}

# Show what else is running in the background, without touching it.
$sysDir = $env:SystemRoot.ToLower()
$heavy = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.MainWindowHandle -eq [IntPtr]::Zero -and $_.WorkingSet64 -gt 150MB -and $_.Path -and
    -not $_.Path.ToLower().StartsWith($sysDir) -and
    "$($_.Name) $($_.Path)" -notmatch $OB_KeepRegex -and
    $_.Name -notmatch '(?i)^(OmniBoost|msedgewebview2|powershell|steam|steamwebhelper|Discord|Spotify)$'
  } | Sort-Object WorkingSet64 -Descending | Select-Object -First 6)
foreach ($h in $heavy) {
  $desc = $h.Name
  try { if ($h.Description) { $desc = "$($h.Description) ($($h.Name).exe)" } } catch {}
  Info "Left running: $desc uses $(Format-Bytes $h.WorkingSet64). Not on the safe list."
}

$parts = @()
if ($stopped -gt 0) { $parts += "$stopped processes stopped ($(Format-Bytes $freedRam) RAM)" }
if ($svcN -gt 0) { $parts += "$svcN updater services set to Manual" }
if ($taskN -gt 0) { $parts += "$taskN telemetry tasks off" }
if ($parts.Count -eq 0) { $parts += 'No unneeded background processes running' }
Result -Summary ($parts -join ', ')
