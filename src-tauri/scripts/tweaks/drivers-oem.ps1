# OEM driver updates (chipset, network, audio, USB...) from Windows Update. GPU drivers are skipped.
Step 'Searching Windows Update for driver updates. This can take a few minutes'
try {
  $session = New-Object -ComObject Microsoft.Update.Session
  $searcher = $session.CreateUpdateSearcher()
  $res = $searcher.Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
} catch { Result -Status 'failed' -Summary "Windows Update unavailable: $($_.Exception.Message)"; return }
$list = @()
foreach ($u in $res.Updates) { if ("$($u.DriverClass)" -notmatch '(?i)^display$') { $list += $u } else { Info "Skipped GPU driver from Windows Update: $($u.Title)" } }
if ($list.Count -eq 0) { Same 'Hardware drivers' 'All up to date'; Result -Summary 'All drivers up to date'; return }
Info "$($list.Count) driver update(s) found"
$reboot = $false; $ok = 0
$stopped = $false
foreach ($u in $list) {
  if (Test-SkipRequested) { $stopped = $true; Info 'Stopped. Remaining driver updates were not installed.'; break }
  $t = "$($u.Title)"
  try {
    if (-not $u.EulaAccepted) { $u.AcceptEula() }
    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
    [void]$coll.Add($u)
    Step "Downloading $t"
    $dl = $session.CreateUpdateDownloader(); $dl.Updates = $coll; [void]$dl.Download()
    Step "Installing $t"
    $inst = $session.CreateUpdateInstaller(); $inst.Updates = $coll
    $r = $inst.Install()
    if ($r.ResultCode -eq 2 -or $r.ResultCode -eq 3) {
      $ok++
      $v = if ($u.DriverVerDate) { ([datetime]$u.DriverVerDate).ToString('yyyy-MM-dd') } else { 'new' }
      Change $t 'Outdated' "Installed ($v)"
      if ($r.RebootRequired) { $reboot = $true }
    } else { Warn "$t failed to install (code $($r.ResultCode))" }
  } catch { Warn "$t : $($_.Exception.Message)" }
}
Result -Status $(if ($stopped) { 'skipped' } else { 'done' }) -Summary "$ok of $($list.Count) driver updates installed" -Reboot $reboot
