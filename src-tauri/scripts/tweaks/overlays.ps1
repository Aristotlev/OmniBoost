# Game overlays and background recording
$onoff = @{ '0' = 'Off'; '1' = 'On'; 'default' = 'On' }
Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0 'DWord' 'Xbox Game Bar background recording' $onoff | Out-Null
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0 'DWord' 'Xbox Game Bar captures' $onoff | Out-Null
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0 'DWord' 'Game DVR (system policy)' @{ '0' = 'Blocked'; '1' = 'Allowed'; 'default' = 'Allowed' } | Out-Null
Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 0 'DWord' 'Open Game Bar with controller button' $onoff | Out-Null
Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'ShowStartupPanel' 0 'DWord' 'Game Bar startup tips' $onoff | Out-Null
$hw = Get-Hardware
$m = @()
if ((Get-RegInfo 'HKCU:\Software\Valve\Steam' 'SteamPath').existed) { $m += (Manual 'Steam overlay' 'Steam > Settings > In Game > turn off "Enable the Steam Overlay while in-game".' 'steam://open/settings') }
if (Test-Path "$env:APPDATA\discord") { $m += (Manual 'Discord overlay' 'Discord > User Settings > Game Overlay > turn off "Enable in-game overlay".' '') }
if ($hw.nvidia) { $m += (Manual 'NVIDIA overlay' 'NVIDIA app > Settings > Features > turn off NVIDIA Overlay (unless you use Instant Replay).' '') }
if ($hw.amd) { $m += (Manual 'AMD overlay' 'AMD Adrenalin > Settings > Preferences > turn off In-Game Overlay.' '') }
$status = if ($m.Count -gt 0) { 'done' } else { 'done' }
Result -Status $status -Summary 'Xbox Game Bar recording off' -Manual $m
