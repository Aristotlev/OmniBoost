# Browser caches (skips browsers that are open)
$freed = 0
$browsers = @(
  @{ n = 'Chrome'; proc = @('chrome'); root = "$env:LOCALAPPDATA\Google\Chrome\User Data"; kind = 'chromium' },
  @{ n = 'Edge'; proc = @('msedge'); root = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"; kind = 'chromium' },
  @{ n = 'Brave'; proc = @('brave'); root = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"; kind = 'chromium' },
  @{ n = 'Opera GX'; proc = @('opera'); root = "$env:LOCALAPPDATA\Opera Software\Opera GX Stable"; kind = 'flat' },
  @{ n = 'Opera'; proc = @('opera'); root = "$env:LOCALAPPDATA\Opera Software\Opera Stable"; kind = 'flat' },
  @{ n = 'Firefox'; proc = @('firefox'); root = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"; kind = 'firefox' }
)
$found = 0
foreach ($b in $browsers) {
  if (-not (Test-Path -LiteralPath $b.root)) { continue }
  $found++
  if (Test-ProcessRunning $b.proc) { Info "$($b.n) is open. Close it to clean its cache next time."; continue }
  Step "Cleaning $($b.n) cache"
  $dirs = @()
  if ($b.kind -eq 'firefox') {
    $dirs = @(Get-ChildItem -LiteralPath $b.root -Directory -ErrorAction SilentlyContinue | ForEach-Object { @{ d = (Join-Path $_.FullName 'cache2'); l = "$($b.n) cache ($($_.Name))" } })
  } elseif ($b.kind -eq 'flat') {
    foreach ($c in @('Cache', 'Code Cache', 'GPUCache')) { $dirs += @{ d = (Join-Path $b.root $c); l = "$($b.n) $c" } }
  } else {
    foreach ($prof in @(Get-ChildItem -LiteralPath $b.root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(Default|Profile \d+)$' })) {
      foreach ($c in @('Cache', 'Code Cache', 'GPUCache')) { $dirs += @{ d = (Join-Path $prof.FullName $c); l = "$($b.n) $c ($($prof.Name))" } }
    }
  }
  foreach ($d in $dirs) { $freed += Clear-Folder $d.d 0 $d.l }
}
if ($found -eq 0) { Result -Status 'skipped' -Summary 'No browsers found'; return }
Result -Summary "Freed $(Format-Bytes $freed)" -Freed $freed
