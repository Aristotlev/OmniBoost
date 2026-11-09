# Stop Windows from throttling background and game processes (EcoQoS)
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1 'DWord' 'Power throttling' @{ '0' = 'On'; '1' = 'Off'; 'default' = 'On' } | Out-Null
Result -Summary 'Power throttling disabled'
