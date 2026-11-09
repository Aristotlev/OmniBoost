# Background apps, widgets and telemetry services
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' 2 'DWord' 'Store apps running in background' @{ '0' = 'User choice'; '1' = 'Allowed'; '2' = 'Blocked'; 'default' = 'Allowed' } | Out-Null
if ((Get-OSBuild) -ge 22000) {
  Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 'DWord' 'Widgets board' @{ '0' = 'Off'; '1' = 'On'; 'default' = 'On' } | Out-Null
} else {
  Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds' 'EnableFeeds' 0 'DWord' 'News and interests on the taskbar' @{ '0' = 'Off'; '1' = 'On'; 'default' = 'On' } | Out-Null
}
$svcs = @(
  @{ n = 'DiagTrack'; l = 'Telemetry service (DiagTrack)' },
  @{ n = 'dmwappushservice'; l = 'WAP push telemetry service' },
  @{ n = 'MapsBroker'; l = 'Downloaded Maps Manager' },
  @{ n = 'RetailDemo'; l = 'Retail Demo service' },
  @{ n = 'Fax'; l = 'Fax service' },
  @{ n = 'WpcMonSvc'; l = 'Parental Controls service' }
)
foreach ($s in $svcs) {
  $w = Get-CimInstance Win32_Service -Filter "Name='$($s.n)'" -ErrorAction SilentlyContinue
  if (-not $w) { continue }
  if ($w.StartMode -eq 'Manual' -or $w.StartMode -eq 'Disabled') { Same $s.l $w.StartMode; continue }
  $delayed = (Get-RegInfo "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.n)" 'DelayedAutostart')
  Add-Backup @{ type = 'service'; key = "service|$($s.n)"; name = $s.n; startMode = $w.StartMode; delayed = [bool]($delayed.existed -and $delayed.value -eq 1) }
  try {
    Set-Service -Name $s.n -StartupType Manual -ErrorAction Stop
    if ($w.State -eq 'Running') { Stop-Service -Name $s.n -Force -ErrorAction SilentlyContinue }
    Change $s.l $w.StartMode 'Manual (stopped)'
  } catch { Warn "$($s.l): $($_.Exception.Message)" }
}
Result -Summary 'Background apps and telemetry trimmed'
