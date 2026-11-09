# Chrome and Edge hardware acceleration off (moves video decoding to the CPU)
$m = @{ '0' = 'Off'; '1' = 'On'; 'default' = 'On' }
Set-Reg 'HKLM:\SOFTWARE\Policies\Google\Chrome' 'HardwareAccelerationModeEnabled' 0 'DWord' 'Chrome hardware acceleration' $m | Out-Null
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'HardwareAccelerationModeEnabled' 0 'DWord' 'Edge hardware acceleration' $m | Out-Null
Result -Summary 'Browser hardware acceleration off (restart the browser)'
