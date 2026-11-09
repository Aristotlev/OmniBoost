# OmniBoost live monitor. Emits one @@MON line every 2 seconds until the app exits.
$parent = 0
if ($env:OMNIBOOST_PARENT) { $parent = [int]$env:OMNIBOOST_PARENT }
$smi = "$env:SystemRoot\System32\nvidia-smi.exe"
$hasSmi = Test-Path $smi
$totalKB = (Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize

while ($true) {
  if ($parent -gt 0 -and -not (Get-Process -Id $parent -ErrorAction SilentlyContinue)) { break }
  $o = @{ t = [DateTimeOffset]::Now.ToUnixTimeMilliseconds() }
  try {
    $p = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop
    $o.cpuLoad = [int]$p.PercentProcessorTime
  } catch {}
  try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $used = $totalKB - $os.FreePhysicalMemory
    $o.ramUsedGB = [math]::Round($used / 1MB, 1)
    $o.ramPct = [int](100 * $used / $totalKB)
  } catch {}
  try {
    $best = $null
    foreach ($z in @(Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction Stop)) {
      $k = if ($z.HighPrecisionTemperature) { $z.HighPrecisionTemperature / 10.0 } else { $z.Temperature }
      if ($k -gt 200) { $c = [math]::Round($k - 273.15, 1); if ($c -gt 5 -and $c -lt 125 -and ($best -eq $null -or $c -gt $best)) { $best = $c } }
    }
    if ($best -ne $null) { $o.cpuTemp = $best }
  } catch {}
  if ($hasSmi) {
    try {
      $q = & $smi --query-gpu=temperature.gpu,utilization.gpu,clocks.gr,power.draw,fan.speed --format=csv,noheader,nounits 2>$null | Select-Object -First 1
      $v = $q -split ',\s*'
      if ($v.Count -ge 5) {
        $o.gpuTemp = [int]$v[0]; $o.gpuLoad = [int]$v[1]; $o.gpuClock = [int]$v[2]
        $pw = 0.0; if ([double]::TryParse($v[3], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$pw)) { $o.gpuPower = [math]::Round($pw) }
        $fs = 0; if ([int]::TryParse($v[4], [ref]$fs)) { $o.gpuFan = $fs }
      }
    } catch {}
  }
  Emit 'MON' $o
  Start-Sleep -Seconds 2
}
