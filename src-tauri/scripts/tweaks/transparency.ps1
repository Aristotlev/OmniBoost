# Transparency effects off
Import-OBWin
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0 'DWord' 'Transparency effects' @{ '0' = 'Off'; '1' = 'On'; 'default' = 'On' } | Out-Null
[OBWin]::Broadcast('ImmersiveColorSet')
Result -Summary 'Transparency effects off'
