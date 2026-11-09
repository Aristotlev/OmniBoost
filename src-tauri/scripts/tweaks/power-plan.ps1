# Max performance power plan: CPU 100%, no core parking, no USB/PCIe/Wi-Fi power saving
$hw = Get-Hardware
Import-OBPower
$aoac = $false; try { $aoac = [OBPower]::IsModernStandby() } catch {}
$prev = Get-ActiveSchemeGuid
$prevName = Get-SchemeName $prev

if ($aoac -or $hw.x3dDual) {
  if ($hw.x3dDual) { Info "$($hw.cpu.Name.Trim()) uses core parking to run games on its V-Cache cores. Keeping the Balanced plan." }
  else { Info 'This device uses Modern Standby, where Windows only supports the Balanced plan. Using the Best performance power mode.' }
  $best = 'ded574b5-45a0-4f42-8737-46345c09c238'
  $cur = [OBPower]::GetOverlay()
  $label = switch ($cur) { '961cc777-2547-4f9d-8174-7d86181b8a7a' { 'Best power efficiency' } '3af9b8d9-7c97-431d-ad78-34a8bfea439f' { 'Better performance' } $best { 'Best performance' } default { 'Balanced' } }
  if ($cur -eq $best) { Same 'Power mode' 'Best performance' }
  else {
    $g = if ($cur) { $cur } else { '00000000-0000-0000-0000-000000000000' }
    Add-Backup @{ type = 'overlay'; key = 'overlay'; guid = $g; label = $label }
    $r = [OBPower]::PowerSetActiveOverlayScheme([Guid]$best)
    if ($r -eq 0) { Change 'Power mode' $label 'Best performance' } else { Warn "Windows refused the power mode change (code $r)" }
  }
  Result -Summary 'Power mode set to Best performance'
  return
}

$ob = $null
foreach ($l in (& powercfg /list)) { if ($l -match 'OmniBoost' -and $l -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $ob = $Matches[1].ToLower() } }
$created = $null
if (-not $ob) {
  Step 'Creating the OmniBoost Ultimate power plan'
  $o = (& powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1) -join ' '
  if ($o -notmatch '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
    $o = (& powercfg -duplicatescheme 8c5e7fda-e8bf-4a96-9a85-cf2e1a7f3254 2>&1) -join ' '
  }
  if ($o -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') {
    $ob = $Matches[1].ToLower(); $created = $ob
    & powercfg -changename $ob 'OmniBoost Ultimate' 'Maximum performance plan created by OmniBoost' | Out-Null
  }
}
if (-not $ob) { Result -Status 'failed' -Summary 'Windows would not create a performance power plan'; return }
if ($prev -ne $ob) { Add-Backup @{ type = 'powerscheme'; key = 'powerscheme'; guid = $prev; created = $created } }

& powercfg -attributes SUB_PROCESSOR CPMINCORES -ATTRIB_HIDE 2>$null | Out-Null
$settings = @(
  @{ sub = 'SUB_PROCESSOR'; set = 'PROCTHROTTLEMIN'; v = 100; label = 'Minimum CPU state'; fmt = '{0}%' },
  @{ sub = 'SUB_PROCESSOR'; set = 'PROCTHROTTLEMAX'; v = 100; label = 'Maximum CPU state'; fmt = '{0}%' },
  @{ sub = 'SUB_PROCESSOR'; set = 'CPMINCORES'; v = 100; label = 'CPU cores kept awake (no parking)'; fmt = '{0}%' },
  @{ sub = '2a737441-1930-4402-8d77-b2bebba308a3'; set = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'; v = 0; label = 'USB selective suspend'; map = @{ 0 = 'Off'; 1 = 'On' } },
  @{ sub = 'SUB_PCIEXPRESS'; set = 'ASPM'; v = 0; label = 'PCIe link power saving'; map = @{ 0 = 'Off'; 1 = 'Moderate'; 2 = 'Maximum' } },
  @{ sub = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'; set = '12bbebe6-58d6-4636-95bb-3217ef867c1a'; v = 0; label = 'Wi-Fi power saving'; map = @{ 0 = 'Max performance'; 1 = 'Low saving'; 2 = 'Medium saving'; 3 = 'Max saving' } },
  @{ sub = 'SUB_DISK'; set = 'DISKIDLE'; v = 0; label = 'Turn off hard disk after'; fmt = '{0} s'; zero = 'Never' }
)
foreach ($s in $settings) {
  $old = Get-PowerAc $prev $s.sub $s.set
  if ($old -eq $null -and $s.label -like 'Wi-Fi*') { continue }
  & powercfg -setacvalueindex $ob $s.sub $s.set $s.v 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) { continue }
  $f = { param($x) if ($x -eq $null) { return 'default' }; if ($s.map) { return $s.map[[int]$x] }; if ($s.zero -and $x -eq 0) { return $s.zero }; return ($s.fmt -f $x) }
  if ($old -eq $s.v) { Same $s.label (& $f $s.v) } else { Change $s.label (& $f $old) (& $f $s.v) }
}
& powercfg /setactive $ob | Out-Null
if ($prev -eq $ob) { Same 'Power plan' 'OmniBoost Ultimate' } else { Change 'Power plan' $prevName 'OmniBoost Ultimate' }
Result -Summary 'OmniBoost Ultimate power plan active'
