# Network adapter power saving off (Energy Efficient Ethernet, Green Ethernet, power saving modes)
$kw = '(?i)^(\*EEE|EEE|AdvancedEEE|EnableGreenEthernet|GreenEthernet|PowerSavingMode|EEELinkAdvertisement|SipsEnabled|ULPMode|EnableExtraPowerSaving|GigaLite|ReduceSpeedOnPowerDown|EnablePowerManagement|\*SelectiveSuspend)$'
$dn = '(?i)(energy.?efficient|green ethernet|power saving mode|advanced eee|\beee\b|gigabit lite|ultra low power|system idle power saver|reduce speed on power down)'
$changed = 0
foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
  $props = @(Get-NetAdapterAdvancedProperty -Name $a.Name -ErrorAction SilentlyContinue | Where-Object { $_.RegistryKeyword -match $kw -or $_.DisplayName -match $dn })
  foreach ($p in $props) {
    $vals = @($p.ValidRegistryValues); $disp = @($p.ValidDisplayValues)
    $idx = -1
    for ($i = 0; $i -lt $disp.Count; $i++) { if ($disp[$i] -match '(?i)^(disabled?|off)$') { $idx = $i; break } }
    if ($idx -lt 0 -and $p.RegistryKeyword -match '(?i)EEE|Green|PowerSaving|GigaLite|ULP|ExtraPowerSaving|ReduceSpeed') { $idx = [array]::IndexOf($vals, '0') }
    if ($idx -lt 0) { continue }
    $off = $vals[$idx]
    $cur = "$(@($p.RegistryValue)[0])"
    $label = "$($a.Name): $($p.DisplayName)"
    if ($cur -eq "$off") { Same $label $disp[$idx]; continue }
    Add-Backup @{ type = 'netadv'; key = "netadv|$($a.Name)|$($p.RegistryKeyword)"; adapter = $a.Name; keyword = $p.RegistryKeyword; value = $cur; label = $p.DisplayName; newLabel = $disp[$idx] }
    try {
      Step "Updating $label (connection drops for a few seconds)"
      Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword $p.RegistryKeyword -RegistryValue $off -ErrorAction Stop
      Change $label $p.DisplayValue $disp[$idx]
      $changed++
    } catch { Warn "$label : $($_.Exception.Message)" }
  }
}
Result -Summary $(if ($changed -gt 0) { "$changed adapter power-saving features off" } else { 'Adapters already tuned' })
