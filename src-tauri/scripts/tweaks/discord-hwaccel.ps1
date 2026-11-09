# Discord hardware acceleration off (frees GPU for the game)
$variants = @(
  @{ n = 'Discord'; dir = "$env:APPDATA\discord"; proc = 'Discord'; lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Discord Inc\Discord.lnk" },
  @{ n = 'Discord PTB'; dir = "$env:APPDATA\discordptb"; proc = 'DiscordPTB'; lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Discord Inc\Discord PTB.lnk" },
  @{ n = 'Discord Canary'; dir = "$env:APPDATA\discordcanary"; proc = 'DiscordCanary'; lnk = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Discord Inc\Discord Canary.lnk" }
)
$closeApps = [bool](Get-Opt 'closeApps' $true)
$found = 0; $manual = @()
foreach ($v in $variants) {
  $f = Join-Path $v.dir 'settings.json'
  if (-not (Test-Path -LiteralPath $f)) { continue }
  $found++
  $j = $null
  try { $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json } catch {}
  if (-not $j) { Warn "$($v.n): could not read settings"; continue }
  if ($j.PSObject.Properties.Name -contains 'enableHardwareAcceleration' -and $j.enableHardwareAcceleration -eq $false) { Same "$($v.n) hardware acceleration" 'Off'; continue }
  $running = [bool](Get-Process -Name $v.proc -ErrorAction SilentlyContinue)
  if ($running -and -not $closeApps) { $manual += (Manual "$($v.n) hardware acceleration" 'Discord > User Settings > Advanced > turn off Hardware Acceleration.' ''); continue }
  if ($running) { Step "Closing $($v.n) to apply"; Stop-Process -Name $v.proc -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2 }
  Add-Backup @{ type = 'file'; key = "file|$f"; path = $f; existed = $true; content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($f)) }
  $j | Add-Member -NotePropertyName 'enableHardwareAcceleration' -NotePropertyValue $false -Force
  [IO.File]::WriteAllText($f, (ConvertTo-Json -InputObject $j -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
  Change "$($v.n) hardware acceleration" 'On' 'Off' $f
  if ($running) {
    if (Test-Path -LiteralPath $v.lnk) { Start-Unelevated $v.lnk; Info "Reopened $($v.n)" } else { $manual += (Manual "Reopen $($v.n)" 'It was closed to apply the setting.' '') }
  }
}
if ($found -eq 0) { Result -Status 'skipped' -Summary 'Discord not installed'; return }
Result -Summary 'Discord no longer uses the GPU' -Manual $manual
