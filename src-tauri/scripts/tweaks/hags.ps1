# Hardware-accelerated GPU scheduling (Windows 10 version 2004 / build 19041 or newer)
$b = Get-OSBuild
if ($b -gt 0 -and $b -lt 19041) { Result -Status 'skipped' -Summary 'Needs Windows 10 version 2004 or newer'; return }
$ok = Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2 'DWord' 'Hardware-accelerated GPU scheduling' @{ '1' = 'Off'; '2' = 'On'; 'default' = 'Off' }
Result -Summary 'GPU scheduling on (applies after restart)' -Reboot $true
