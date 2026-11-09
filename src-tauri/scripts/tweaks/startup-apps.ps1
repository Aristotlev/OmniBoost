# Disable non-essential startup apps (reversible, same switch as Task Manager > Startup)
$keep = $OB_KeepRegex
$sources = @(
  @{ run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; appr = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' },
  @{ run = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; appr = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run' },
  @{ run = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; appr = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32' }
)
$items = @()
foreach ($s in $sources) {
  $k = Get-Item -LiteralPath $s.run -ErrorAction SilentlyContinue
  if (-not $k) { continue }
  foreach ($n in $k.GetValueNames()) { if ($n) { $items += @{ name = $n; cmd = "$($k.GetValue($n))"; appr = $s.appr } } }
}
$folders = @(
  @{ dir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; appr = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' },
  @{ dir = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"; appr = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder' }
)
foreach ($f in $folders) {
  foreach ($file in @(Get-ChildItem -LiteralPath $f.dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
    $items += @{ name = $file.Name; cmd = $file.FullName; appr = $f.appr }
  }
}
if ($items.Count -eq 0) { Result -Status 'skipped' -Summary 'No startup apps found'; return }
$ft = [BitConverter]::GetBytes((Get-Date).ToFileTime())
$disabled = 0; $kept = 0
foreach ($i in $items) {
  $label = "Startup: $($i.name -replace '\.lnk$', '')"
  if ("$($i.name) $($i.cmd)" -match $keep) { Same $label 'Kept (driver, security or device app)'; $kept++; continue }
  $cur = Get-RegInfo $i.appr $i.name
  if ($cur.existed -and $cur.kind -eq 'Binary' -and ([byte[]]$cur.value)[0] % 2 -eq 1) { Same $label 'Disabled'; continue }
  [byte[]]$val = @(3, 0, 0, 0) + $ft
  $info = Backup-Reg $i.appr $i.name
  try {
    Ensure-RegKey $i.appr
    New-ItemProperty -LiteralPath $i.appr -Name $i.name -Value $val -PropertyType Binary -Force -ErrorAction Stop | Out-Null
    Change $label 'Enabled' 'Disabled' (Show-RegPath $i.appr $i.name)
    $disabled++
  } catch { Warn "$label : $($_.Exception.Message)" }
}
Result -Summary "$disabled startup apps disabled, $kept essential kept"
