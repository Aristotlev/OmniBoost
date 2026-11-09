# Most played games: high performance GPU and high CPU priority
$games = Get-Games 10
if ($games.Count -eq 0) { Result -Status 'skipped' -Summary 'No Steam, Epic or Riot games found'; return }
$gp = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$gpuMap = @{ 'GpuPreference=0;' = 'Let Windows decide'; 'GpuPreference=1;' = 'Power saving'; 'GpuPreference=2;' = 'High performance'; 'default' = 'Let Windows decide' }
$cpuMap = @{ '1' = 'Idle'; '2' = 'Normal'; '3' = 'High'; '5' = 'Below normal'; '6' = 'Above normal'; 'default' = 'Normal' }
foreach ($g in $games) {
  if (Test-SkipRequested) { Info 'Stopped. Remaining games were not changed.'; break }
  Step "Prioritizing $($g.name)"
  $info = Get-RegInfo $gp $g.exe
  $pairs = [ordered]@{}
  if ($info.existed -and $info.value) { foreach ($kv in ("$($info.value)" -split ';')) { if ($kv -match '^\s*([^=]+)=(.*)$') { $pairs[$Matches[1].Trim()] = $Matches[2].Trim() } } }
  $pairs['GpuPreference'] = '2'
  $str = (($pairs.Keys | ForEach-Object { "$_=$($pairs[$_])" }) -join ';') + ';'
  Set-Reg $gp $g.exe $str 'String' "$($g.name): graphics preference" $gpuMap | Out-Null
  if ($g.source -eq 'Riot') { Info "$($g.name): CPU priority left to Riot Vanguard"; continue }
  $exeName = Split-Path $g.exe -Leaf
  Set-Reg "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$exeName\PerfOptions" 'CpuPriorityClass' 3 'DWord' "$($g.name): CPU priority" $cpuMap | Out-Null
}
Result -Summary "$($games.Count) games set to high performance"
