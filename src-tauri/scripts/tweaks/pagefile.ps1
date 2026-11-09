# Page file: system managed (sized by Windows from installed RAM)
$cs = Get-CimInstance Win32_ComputerSystem
$ram = [math]::Round($cs.TotalPhysicalMemory / 1GB)
Info "Installed RAM: $ram GB"
if ($cs.AutomaticManagedPagefile) { Same 'Page file' 'System managed'; Result -Summary 'Page file already optimal'; return }
$files = @(Get-CimInstance Win32_PageFileSetting -ErrorAction SilentlyContinue | ForEach-Object { @{ name = $_.Name; initial = $_.InitialSize; max = $_.MaximumSize } })
Add-Backup @{ type = 'pagefile'; key = 'pagefile'; files = $files }
try {
  Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop
  $was = if ($files.Count -gt 0) { 'Custom size' } else { 'Disabled' }
  Change 'Page file' $was 'System managed'
  Result -Summary 'Page file set to system managed' -Reboot $true
} catch { Result -Status 'failed' -Summary $_.Exception.Message }
