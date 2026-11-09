# Memory Integrity (HVCI) off. Opt-in: lowers kernel protection.
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 0 'DWord' 'Memory Integrity (Core isolation)' @{ '0' = 'Off'; '1' = 'On'; 'default' = 'Off' } | Out-Null
Result -Summary 'Memory Integrity off (applies after restart)' -Reboot $true
