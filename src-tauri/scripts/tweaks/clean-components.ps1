# DISM component store cleanup with live progress.
# DISM is never killed: on Skip, or after 20 minutes, OmniBoost stops waiting and DISM finishes in the background.
function Get-DismPercent([string]$Path) {
  try {
    $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
      $n = [int][math]::Min($fs.Length, 4096)
      if ($n -le 0) { return $null }
      [void]$fs.Seek(-$n, [IO.SeekOrigin]::End)
      $buf = New-Object byte[] $n
      [void]$fs.Read($buf, 0, $n)
    } finally { $fs.Dispose() }
    $txt = [Text.Encoding]::ASCII.GetString([byte[]]@($buf | Where-Object { $_ -ne 0 }))
    $m = [regex]::Matches($txt, '(\d{1,3})(?:[.,]\d)?\s*%')
    if ($m.Count -gt 0) { return [int]$m[$m.Count - 1].Groups[1].Value }
  } catch {}
  return $null
}
$drive = Get-SysDriveLetter
$before = Get-DriveFree $drive
$log = Join-Path $OB_Root ("run\dism-{0}.log" -f $PID)
$max = 20
Step 'Starting DISM component cleanup'
$p = Start-Process -FilePath "$env:SystemRoot\System32\Dism.exe" -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup', '/NoRestart' -NoNewWindow -PassThru -RedirectStandardOutput $log
$null = $p.Handle
$t0 = Get-Date
$detached = $false
while (-not $p.HasExited) {
  Start-Sleep -Milliseconds 1500
  $el = Format-Elapsed ((Get-Date) - $t0)
  $pct = Get-DismPercent $log
  if ($null -ne $pct) { Step "Cleaning the component store, $pct%, $el" $pct } else { Step "Cleaning the component store, $el" }
  if (Test-SkipRequested) { $detached = $true; Info 'Stopped waiting. DISM keeps running in the background and finishes on its own.'; break }
  if (((Get-Date) - $t0).TotalMinutes -ge $max) { $detached = $true; Info "DISM is still running after $max minutes. It keeps going in the background and finishes on its own."; break }
}
if (-not $detached) {
  $code = $p.ExitCode
  if ($code -eq 0) { Info 'Component store cleaned' } else { Warn "DISM finished with code $code" }
  Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
}
$after = Get-DriveFree $drive
$freed = [math]::Max(0, $after - $before)
Change "Free space on ${drive}:" (Format-Bytes $before) (Format-Bytes $after)
if ($detached) { Result -Status 'done' -Summary "Running in the background, freed $(Format-Bytes $freed) so far" -Freed $freed }
else { Result -Summary "Freed $(Format-Bytes $freed)" -Freed $freed }
