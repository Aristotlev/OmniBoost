# Windows Game Mode
$m = @{ '0' = 'Off'; '1' = 'On'; 'default' = 'Default' }
Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1 'DWord' 'Game Mode' $m | Out-Null
Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1 'DWord' 'Game Mode automatic switching' $m | Out-Null
Result -Summary 'Game Mode on'
