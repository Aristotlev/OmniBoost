# Multimedia scheduler: give games CPU and GPU priority, remove network throttling
$base = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
Set-Reg $base 'NetworkThrottlingIndex' -1 'DWord' 'Network throttling' @{ '10' = 'On (10)'; '-1' = 'Off'; 'default' = 'On' } | Out-Null
Set-Reg $base 'SystemResponsiveness' 10 'DWord' 'CPU reserved for background tasks' @{ '20' = '20%'; '10' = '10%'; 'default' = '20%' } | Out-Null
$g = "$base\Tasks\Games"
Set-Reg $g 'GPU Priority' 8 'DWord' 'Games: GPU priority' | Out-Null
Set-Reg $g 'Priority' 6 'DWord' 'Games: CPU priority' | Out-Null
Set-Reg $g 'Scheduling Category' 'High' 'String' 'Games: scheduling category' | Out-Null
Set-Reg $g 'SFIO Priority' 'High' 'String' 'Games: disk I/O priority' | Out-Null
Result -Summary 'Game scheduling profile applied' -Reboot $true
