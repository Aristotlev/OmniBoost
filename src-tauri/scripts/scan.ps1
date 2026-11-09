# OmniBoost system scan. Emits one @@SCAN line with the full JSON report.

$issues = New-Object System.Collections.ArrayList
function Issue([string]$Severity, [string]$Area, [string]$Title, [string]$Detail, [string]$Fix = '', [string]$Open = '') {
  $o = @{ severity = $Severity; area = $Area; title = $Title; detail = $Detail; fix = $Fix }
  if ($Open) { $o.open = $Open }
  [void]$issues.Add($o)
}
function Safe([scriptblock]$B) { try { & $B } catch { $null } }

Step 'Reading system'
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$hw = Get-Hardware
$cpu = $hw.cpu
$chassis = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue).ChassisTypes)
$isLaptop = $hw.battery -or (@($chassis | Where-Object { @(8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32) -contains $_ }).Count -gt 0)
$board = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue

# ---------- GPU ----------
Step 'Reading graphics'
$smi = "$env:SystemRoot\System32\nvidia-smi.exe"
$nv = $null
if (Test-Path $smi) {
  $q = Safe { & $smi --query-gpu=name,temperature.gpu,utilization.gpu,pcie.link.width.current,pcie.link.width.max,pcie.link.gen.max,driver_version --format=csv,noheader,nounits 2>$null | Select-Object -First 1 }
  if ($q) { $p = $q -split ',\s*'; if ($p.Count -ge 7) { $nv = @{ name = $p[0]; temp = [int]$p[1]; load = [int]$p[2]; widthCur = [int]$p[3]; widthMax = [int]$p[4]; genMax = $p[5]; driver = $p[6] } } }
}
$gpus = @()
foreach ($g in $hw.gpus) {
  $vendor = if ($g.Name -match '(?i)nvidia') { 'NVIDIA' } elseif ($g.Name -match '(?i)(amd|radeon)') { 'AMD' } elseif ($g.Name -match '(?i)intel') { 'Intel' } else { 'Other' }
  $date = $null; $age = $null
  if ($g.DriverDate) { $date = $g.DriverDate; $age = [int]((Get-Date) - $g.DriverDate).TotalDays }
  $ver = $g.DriverVersion
  if ($vendor -eq 'NVIDIA' -and $ver) { $d = ($ver -replace '\.', ''); if ($d.Length -ge 5) { $t = $d.Substring($d.Length - 5); $ver = $t.Substring(0, 3) + '.' + $t.Substring(3) } }
  $vram = $null
  if ($g.AdapterRAM -and $g.AdapterRAM -gt 0) { $vram = [math]::Round($g.AdapterRAM / 1GB, 1) }
  $gpus += @{ name = $g.Name; vendor = $vendor; driver = $ver; driverDate = $(if ($date) { $date.ToString('yyyy-MM-dd') } else { $null }); driverAgeDays = $age; vramGB = $vram }
  if ($age -ne $null -and $age -gt 120 -and $vendor -ne 'Other') {
    $url = switch ($vendor) { 'NVIDIA' { 'https://www.nvidia.com/en-us/drivers/' } 'AMD' { 'https://www.amd.com/en/support/download/drivers.html' } default { 'https://www.intel.com/content/www/us/en/support/detect.html' } }
    Issue 'warning' 'Drivers' "$vendor driver is $age days old" "$($g.Name) runs driver $ver. New drivers add game-specific performance fixes." 'Update GPU driver' $url
  }
}
if ($nv) {
  if ($nv.widthMax -ge 8 -and $nv.widthCur -lt $nv.widthMax) { Issue 'critical' 'Hardware' "GPU running at PCIe x$($nv.widthCur) instead of x$($nv.widthMax)" 'The graphics card is not using all PCIe lanes. Reseat the card in the top x16 slot and check the riser cable if you use one.' }
  if ($nv.temp -ge 85) { Issue 'critical' 'Thermals' "GPU is hot: $($nv.temp) C" 'Clean dust filters, check case airflow and GPU fan curve.' }
}

# ---------- CPU / temps ----------
Step 'Reading temperatures'
$cpuTemp = $null
$tz = Safe { Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction Stop }
foreach ($z in @($tz)) {
  $k = if ($z.HighPrecisionTemperature) { $z.HighPrecisionTemperature / 10.0 } else { $z.Temperature }
  if ($k -gt 200) { $c = [math]::Round($k - 273.15, 1); if ($c -gt 5 -and $c -lt 125 -and ($cpuTemp -eq $null -or $c -gt $cpuTemp)) { $cpuTemp = $c } }
}
if ($cpuTemp -ne $null -and $cpuTemp -ge 90) { Issue 'critical' 'Thermals' "System is hot: $cpuTemp C" 'Check CPU cooler mounting, thermal paste and case airflow.' }

# ---------- RAM ----------
Step 'Checking memory'
$mods = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
$ramModules = @()
$channels = @()
$memType = 'Unknown'
foreach ($m in $mods) {
  $loc = "$($m.BankLabel) $($m.DeviceLocator)"
  $ch = $null
  if ($loc -match '(?i)channel\s*-?\s*([A-H])\b') { $ch = $Matches[1].ToUpper() }
  elseif ($m.DeviceLocator -match '(?i)DIMM[_\s-]?([A-H])\d') { $ch = $Matches[1].ToUpper() }
  elseif ($m.DeviceLocator -match '(?i)^([A-H])\d$') { $ch = $Matches[1].ToUpper() }
  if ($ch) { $channels += $ch }
  $type = switch ([int]$m.SMBIOSMemoryType) { 26 { 'DDR4' } 34 { 'DDR5' } 24 { 'DDR3' } 35 { 'LPDDR5' } 30 { 'LPDDR4' } default { 'Unknown' } }
  if ($type -ne 'Unknown') { $memType = $type }
  $rated = $null
  foreach ($x in [regex]::Matches("$($m.PartNumber)", '(?<!\d)(\d{4})(?!\d)')) {
    $n = [int]$x.Value
    if (($type -eq 'DDR4' -and $n -ge 2400 -and $n -le 5333) -or ($type -eq 'DDR5' -and $n -ge 4800 -and $n -le 9600)) { $rated = $n; break }
  }
  $ramModules += @{ slot = $m.DeviceLocator; bank = $m.BankLabel; channel = $ch; capacityGB = [math]::Round($m.Capacity / 1GB); speed = [int]$m.Speed; configured = [int]$m.ConfiguredClockSpeed; manufacturer = "$($m.Manufacturer)".Trim(); part = "$($m.PartNumber)".Trim(); type = $type; ratedFromPart = $rated; formFactor = [int]$m.FormFactor }
}
$totalRam = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$dual = $null
if ($mods.Count -eq 1) {
  $dual = $false
  Issue 'warning' 'Memory' 'RAM is running in single channel' "Only one memory stick is installed ($($ramModules[0].capacityGB) GB). A matching second stick doubles memory bandwidth and raises FPS in CPU-heavy games."
} elseif ($mods.Count -ge 2) {
  $uniq = @($channels | Select-Object -Unique)
  if ($channels.Count -eq $mods.Count -and $uniq.Count -eq 1) {
    $dual = $false
    Issue 'critical' 'Memory' 'Both RAM sticks are in the same channel' "All sticks report channel $($uniq[0]). Move them to the slots your motherboard manual marks for dual channel (usually A2 and B2)."
  } elseif ($uniq.Count -ge 2) { $dual = $true }
  $caps = @($ramModules | ForEach-Object { $_.capacityGB } | Select-Object -Unique)
  if ($caps.Count -gt 1) { Issue 'info' 'Memory' 'Mixed RAM stick sizes' "Sticks of different sizes ($($caps -join ' / ') GB) run partly in single channel (flex mode)." }
}
$desktopDimm = @($ramModules | Where-Object { $_.formFactor -eq 8 }).Count -gt 0
if ($desktopDimm -and $ramModules.Count -gt 0) {
  $cfg = ($ramModules | Measure-Object -Property configured -Minimum).Minimum
  $rated = ($ramModules | ForEach-Object { $_.ratedFromPart } | Where-Object { $_ } | Measure-Object -Maximum).Maximum
  $xmpOff = $false
  if ($rated -and $cfg -and $cfg -lt ($rated * 0.92)) { $xmpOff = $true }
  elseif (-not $rated -and (($memType -eq 'DDR4' -and $cfg -le 2666) -or ($memType -eq 'DDR5' -and $cfg -le 4800))) { $xmpOff = $true }
  if ($xmpOff) {
    $r = if ($rated) { "$rated MT/s" } else { 'its rated speed' }
    Issue 'critical' 'Memory' 'RAM is running below its rated speed' "Memory runs at $cfg MT/s but is rated for $r. Enable XMP (Intel) or EXPO (AMD) in the BIOS. Windows apps cannot change this."
  }
}

# ---------- storage ----------
Step 'Checking drives'
$disks = @()
foreach ($pd in @(Get-PhysicalDisk -ErrorAction SilentlyContinue)) {
  $rel = Safe { $pd | Get-StorageReliabilityCounter -ErrorAction Stop }
  $media = "$($pd.MediaType)"
  if ($media -eq 'Unspecified' -and "$($pd.BusType)" -eq 'NVMe') { $media = 'SSD' }
  $d = @{ name = $pd.FriendlyName; media = $media; bus = "$($pd.BusType)"; sizeGB = [math]::Round($pd.Size / 1GB); health = "$($pd.HealthStatus)"; temp = $(if ($rel) { $rel.Temperature } else { $null }); wear = $(if ($rel) { $rel.Wear } else { $null }); readErrors = $(if ($rel) { $rel.ReadErrorsUncorrected } else { $null }) }
  $disks += $d
  if ($d.health -and $d.health -ne 'Healthy') { Issue 'critical' 'Storage' "Drive health: $($d.health)" "$($d.name) reports a $($d.health) status. Back up your data now." }
  if ($d.wear -ne $null -and $d.wear -ge 80) { Issue 'warning' 'Storage' "SSD wear at $($d.wear)%" "$($d.name) is near the end of its rated write life." }
  if ($d.temp -ne $null -and $d.temp -ge 70) { Issue 'warning' 'Thermals' "Drive is hot: $($d.temp) C" "$($d.name) may throttle. Add airflow or an M.2 heatsink." }
  if ($d.readErrors -ne $null -and $d.readErrors -gt 0) { Issue 'critical' 'Storage' 'Uncorrected read errors' "$($d.name) logged $($d.readErrors) uncorrected read errors." }
}
$volumes = @()
foreach ($v in @(Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter })) {
  $volumes += @{ letter = "$($v.DriveLetter)"; label = $v.FileSystemLabel; sizeGB = [math]::Round($v.Size / 1GB); freeGB = [math]::Round($v.SizeRemaining / 1GB, 1) }
  if ($v.Size -gt 0 -and ($v.SizeRemaining / $v.Size) -lt 0.1) { Issue 'warning' 'Storage' "Drive $($v.DriveLetter): is almost full" "Only $([math]::Round($v.SizeRemaining / 1GB, 1)) GB free. Full drives slow down loading and updates." }
}

# ---------- displays ----------
Step 'Reading displays'
$displays = @()
try {
  Import-OBDisplay
  foreach ($l in [OBDisplay]::List()) {
    $p = $l -split '\|'
    $displays += @{ device = $p[0]; name = $p[1]; width = [int]$p[2]; height = [int]$p[3]; hz = [int]$p[4]; maxHz = [int]$p[5]; primary = ($p[6] -eq '1') }
    if ([int]$p[5] -gt [int]$p[4]) { Issue 'warning' 'Display' "Monitor running at $($p[4]) Hz" "$($p[1]) supports $($p[5]) Hz at this resolution. Boost switches it." }
  }
} catch {}

# ---------- hardware faults ----------
Step 'Looking for hardware errors'
$since = (Get-Date).AddDays(-30)
$whea = @(Safe { Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-WHEA-Logger'; StartTime = $since } -MaxEvents 200 -ErrorAction Stop } | Where-Object { $_ })
if ($whea.Count -gt 0) { Issue 'critical' 'Hardware' "$($whea.Count) hardware errors in 30 days" 'Windows logged WHEA hardware errors. Common causes: unstable overclock or XMP, failing RAM, CPU or PCIe device. Run Windows Memory Diagnostic.' }
$kp = @(Safe { Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $since } -MaxEvents 100 -ErrorAction Stop } | Where-Object { $_ })
if ($kp.Count -gt 0) { Issue 'warning' 'Hardware' "$($kp.Count) unexpected shutdowns in 30 days" 'The PC lost power or crashed without shutting down. Check PSU, temperatures and overclock stability.' }
$bad = @(Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne 22 -and $_.ConfigManagerErrorCode -ne 45 })
foreach ($b in ($bad | Select-Object -First 6)) {
  $why = if ($b.ConfigManagerErrorCode -eq 28) { 'Driver not installed' } else { "Device error code $($b.ConfigManagerErrorCode)" }
  Issue 'warning' 'Drivers' "$why" "$($b.Name) is not working properly. Boost searches Windows Update for a driver."
}

# ---------- battery ----------
$battery = $null
if ($hw.battery) {
  $full = Safe { (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop | Select-Object -First 1).FullChargedCapacity }
  $design = Safe { (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction Stop | Select-Object -First 1).DesignedCapacity }
  $wear = $null
  if ($full -and $design -and $design -gt 0) { $wear = [math]::Round((1 - $full / $design) * 100) }
  $battery = @{ wearPct = $wear }
  if ($wear -ne $null -and $wear -ge 30) { Issue 'warning' 'Hardware' "Battery has lost $wear% capacity" 'A worn battery can trigger lower performance modes on battery power.' }
}

# ---------- current settings worth fixing ----------
Step 'Reading Windows settings'
$active = Get-ActiveSchemeGuid
$schemeName = if ($active) { Get-SchemeName $active } else { 'Unknown' }
$dvr = (Get-RegInfo 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled')
if (-not $dvr.existed -or $dvr.value -ne 0) { Issue 'info' 'Windows' 'Xbox Game Bar recording is on' 'Background capture costs FPS. Boost turns it off.' }
$hvci = Get-RegInfo 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled'
$hvciOn = ($hvci.existed -and $hvci.value -eq 1)
if ($hvciOn) { Issue 'info' 'Windows' 'Memory Integrity is on' 'Costs some performance in games. Optional toggle in the Boost plan.' }
$hags = Get-RegInfo 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
if ((Get-OSBuild) -ge 19041 -and (-not $hags.existed -or $hags.value -ne 2)) { Issue 'info' 'Graphics' 'Hardware-accelerated GPU scheduling is off' 'Lowers CPU overhead and is required for DLSS Frame Generation.' }
if ($schemeName -notmatch '(?i)(ultimate|high|omniboost)') { Issue 'info' 'Power' "Power plan: $schemeName" 'The CPU is allowed to downclock and park cores. Boost switches to a max performance plan.' }

$startup = 0
foreach ($k in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')) {
  $i = Get-Item -LiteralPath $k -ErrorAction SilentlyContinue
  if ($i) { $startup += @($i.GetValueNames() | Where-Object { $_ }).Count }
}
$startup += @(Get-ChildItem -Path "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp" -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' }).Count

Step 'Finding games'
$games = Get-Games 12

$crit = @($issues | Where-Object { $_.severity -eq 'critical' }).Count
$warn = @($issues | Where-Object { $_.severity -eq 'warning' }).Count
$inf = @($issues | Where-Object { $_.severity -eq 'info' }).Count
$score = [math]::Max(5, 100 - 18 * $crit - 8 * $warn - 3 * $inf)

$report = @{
  os = @{ name = $os.Caption; version = $os.Version; build = $os.BuildNumber }
  machine = @{ name = $env:COMPUTERNAME; maker = $cs.Manufacturer; model = $cs.Model; board = $(if ($board) { "$($board.Manufacturer) $($board.Product)" } else { '' }); laptop = [bool]$isLaptop }
  cpu = @{ name = "$($cpu.Name)".Trim(); cores = $cpu.NumberOfCores; threads = $cpu.NumberOfLogicalProcessors; maxMHz = $cpu.MaxClockSpeed; x3dDual = $hw.x3dDual }
  gpus = $gpus
  nvidia = $nv
  ram = @{ totalGB = $totalRam; type = $memType; modules = $ramModules; dualChannel = $dual }
  disks = $disks
  volumes = $volumes
  displays = $displays
  battery = $battery
  temps = @{ cpu = $cpuTemp; gpu = $(if ($nv) { $nv.temp } else { $null }) }
  power = @{ scheme = $schemeName }
  startupCount = $startup
  games = $games
  issues = @($issues.ToArray())
  score = $score
  hasBackup = (Test-Path -LiteralPath $OB_Backup) -and ((Get-Backup).Count -gt 0)
  vendors = @{ nvidia = $hw.nvidia; amd = $hw.amd }
  apps = @{
    discord = (Test-Path "$env:APPDATA\discord\settings.json")
    steam = [bool](Get-RegInfo 'HKCU:\Software\Valve\Steam' 'SteamPath').existed
    chrome = (Test-Path "$env:LOCALAPPDATA\Google\Chrome\User Data")
    edge = (Test-Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data")
  }
}
Emit 'SCAN' $report
