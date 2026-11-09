# Temp files and junk
$freed = 0
$targets = @(
  @{ p = "$env:SystemRoot\Temp"; l = 'Windows temp folder' },
  @{ p = "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"; l = 'Error reports (archive)' },
  @{ p = "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"; l = 'Error reports (queue)' },
  @{ p = "$env:SystemRoot\LiveKernelReports"; l = 'Kernel live dumps' }
)
foreach ($u in @(Get-ChildItem -LiteralPath "$env:SystemDrive\Users" -Directory -Force -ErrorAction SilentlyContinue)) {
  $t = Join-Path $u.FullName 'AppData\Local\Temp'
  if (Test-Path -LiteralPath $t) { $targets += @{ p = $t; l = "Temp files ($($u.Name))" } }
  $c = Join-Path $u.FullName 'AppData\Local\CrashDumps'
  if (Test-Path -LiteralPath $c) { $targets += @{ p = $c; l = "Crash dumps ($($u.Name))" } }
}
foreach ($t in $targets) {
  Step "Cleaning $($t.l)"
  $freed += Clear-Folder $t.p 24 $t.l
}
$dmp = "$env:SystemRoot\MEMORY.DMP"
if (Test-Path -LiteralPath $dmp) {
  $sz = (Get-Item -LiteralPath $dmp -Force).Length
  try { Remove-Item -LiteralPath $dmp -Force -ErrorAction Stop; $freed += $sz; Change 'Full memory dump' (Format-Bytes $sz) 'deleted' } catch {}
}
Result -Summary "Freed $(Format-Bytes $freed)" -Freed $freed
