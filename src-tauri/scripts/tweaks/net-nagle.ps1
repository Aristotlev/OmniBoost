# Nagle's algorithm off: sends small packets immediately (helps TCP games such as MMOs)
$base = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
$names = @{}
foreach ($a in @(Get-NetAdapter -ErrorAction SilentlyContinue)) { $names["$($a.InterfaceGuid)".ToLower()] = $a.Name }
$n = 0
foreach ($k in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue)) {
  $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
  $ip = "$($p.DhcpIPAddress)"; if (-not $ip -or $ip -eq '0.0.0.0') { $ip = "$(@($p.IPAddress)[0])" }
  if (-not $ip -or $ip -eq '0.0.0.0') { continue }
  $guid = $k.PSChildName.ToLower()
  $nm = if ($names.ContainsKey($guid)) { $names[$guid] } else { $ip }
  $path = "$base\$($k.PSChildName)"
  Set-Reg $path 'TcpAckFrequency' 1 'DWord' "${nm}: delayed ACK" @{ '1' = 'Off (ack every packet)'; '2' = 'On'; 'default' = 'On' } | Out-Null
  Set-Reg $path 'TCPNoDelay' 1 'DWord' "${nm}: Nagle's algorithm" @{ '1' = 'Off'; '0' = 'On'; 'default' = 'On' } | Out-Null
  $n++
}
if ($n -eq 0) { Result -Status 'skipped' -Summary 'No connected network adapters'; return }
Result -Summary "Nagle off on $n connection(s)" -Reboot $true
