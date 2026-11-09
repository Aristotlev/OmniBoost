# AMD Radeon settings checklist (applied in AMD Software: Adrenalin Edition)
$hw = Get-Hardware
if (-not $hw.amd) { Result -Status 'skipped' -Summary 'No AMD GPU found'; return }
$adr = "$env:ProgramFiles\AMD\CNext\CNext\RadeonSoftware.exe"
$open = if (Test-Path -LiteralPath $adr) { $adr } else { 'https://www.amd.com/en/support/download/drivers.html' }
$m = @(
  (Manual 'AMD Adrenalin > Gaming > Graphics' 'Radeon Anti-Lag: On. Radeon Boost: Off. Radeon Chill: Off. Enhanced Sync: Off. Texture Filtering Quality: Performance. Tessellation Mode: AMD optimized. Surface Format Optimization: On.' $open),
  (Manual 'AMD Adrenalin > Gaming > Display' 'AMD FreeSync: On for your monitor.' $open)
)
Info 'AMD does not expose these settings to scripts. Your checklist is ready.'
Result -Status 'manual' -Summary '2 quick settings in AMD Adrenalin' -Manual $m
