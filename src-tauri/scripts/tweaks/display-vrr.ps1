# Variable refresh rate and optimizations for windowed games
$path = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
$name = 'DirectXUserGlobalSettings'
$info = Get-RegInfo $path $name
$pairs = [ordered]@{}
if ($info.existed -and $info.value) { foreach ($kv in ("$($info.value)" -split ';')) { if ($kv -match '^\s*([^=]+)=(.*)$') { $pairs[$Matches[1].Trim()] = $Matches[2].Trim() } } }
$win11 = (Get-OSBuild) -ge 22000
$pairs['VRROptimizeEnable'] = '1'
if ($win11) { $pairs['SwapEffectUpgradeEnable'] = '1' }
$str = (($pairs.Keys | ForEach-Object { "$_=$($pairs[$_])" }) -join ';') + ';'
$label = if ($win11) { 'Windowed game optimizations + VRR' } else { 'Variable refresh rate for games' }
Set-Reg $path $name $str 'String' $label | Out-Null
if (-not $win11) { Info 'Optimizations for windowed games is a Windows 11 feature. Variable refresh rate applied.' }
Result -Summary $(if ($win11) { 'VRR and windowed game optimizations on' } else { 'Variable refresh rate on' })
