# Chrome and Edge: no background running after close, no startup boost
$m = @{ '0' = 'Off'; '1' = 'On'; 'default' = 'On' }
$c = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
$e = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
if (Test-Path "$env:LOCALAPPDATA\Google\Chrome\User Data") { Set-Reg $c 'BackgroundModeEnabled' 0 'DWord' 'Chrome keeps running after close' $m | Out-Null }
if (Test-Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data") {
  Set-Reg $e 'BackgroundModeEnabled' 0 'DWord' 'Edge keeps running after close' $m | Out-Null
  Set-Reg $e 'StartupBoostEnabled' 0 'DWord' 'Edge startup boost (preloads at boot)' $m | Out-Null
}
Result -Summary 'Browsers stop running in the background'
