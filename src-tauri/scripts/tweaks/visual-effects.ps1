# Performance Options > Visual Effects: best performance, keep smooth fonts and thumbnails
Import-OBWin
$desk = 'HKCU:\Control Panel\Desktop'
[void](Backup-Reg $desk 'UserPreferencesMask')
[void](Backup-Reg $desk 'DragFullWindows')
[void](Backup-Reg "$desk\WindowMetrics" 'MinAnimate')
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 3 'DWord' 'Visual effects mode' @{ '0' = 'Let Windows choose'; '1' = 'Best appearance'; '2' = 'Best performance'; '3' = 'Custom (OmniBoost)'; 'default' = 'Let Windows choose' } | Out-Null
$onoff = @{ '0' = 'Off'; '1' = 'On'; 'default' = 'On' }
$adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Set-Reg $adv 'TaskbarAnimations' 0 'DWord' 'Taskbar animations' $onoff | Out-Null
Set-Reg $adv 'ListviewAlphaSelect' 0 'DWord' 'Translucent selection rectangle' $onoff | Out-Null
Set-Reg $adv 'ListviewShadow' 0 'DWord' 'Shadows under desktop icon labels' $onoff | Out-Null
Set-Reg $adv 'IconsOnly' 0 'DWord' 'Show thumbnails instead of icons' @{ '0' = 'On'; '1' = 'Off'; 'default' = 'On' } | Out-Null
Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 0 'DWord' 'Peek' $onoff | Out-Null
Set-Reg $desk 'FontSmoothing' '2' 'String' 'Smooth edges of screen fonts' @{ '0' = 'Off'; '2' = 'On'; 'default' = 'On' } | Out-Null

# Live effects through SystemParametersInfo (GET = SET - 1)
$fx = @(
  @{ set = 0x1003; label = 'Animate menus' },
  @{ set = 0x1005; label = 'Slide open combo boxes' },
  @{ set = 0x1007; label = 'Smooth-scroll list boxes' },
  @{ set = 0x1013; label = 'Fade menus' },
  @{ set = 0x1015; label = 'Fade menu items after clicking' },
  @{ set = 0x1017; label = 'Animate tooltips' },
  @{ set = 0x101B; label = 'Shadow under mouse pointer' },
  @{ set = 0x1025; label = 'Shadows under windows' },
  @{ set = 0x1043; label = 'Animate controls inside windows' }
)
foreach ($e in $fx) {
  $cur = [OBWin]::GetBool([uint32]($e.set - 1))
  if (-not $cur) { Same $e.label 'Off'; continue }
  Add-Backup @{ type = 'spi'; key = "spi|$($e.set)"; action = $e.set; value = $true; label = $e.label }
  [void][OBWin]::SetBool([uint32]$e.set, $false)
  Change $e.label 'On' 'Off'
}
if ([OBWin]::GetMinAnimate()) {
  Add-Backup @{ type = 'spi'; key = 'spi|anim'; action = 0x0049; anim = $true; value = $true; label = 'Animate windows when minimizing and maximizing' }
  [void][OBWin]::SetMinAnimate($false)
  Change 'Animate windows when minimizing and maximizing' 'On' 'Off'
} else { Same 'Animate windows when minimizing and maximizing' 'Off' }
if ([OBWin]::GetBool(0x0026)) {
  Add-Backup @{ type = 'spi'; key = 'spi|drag'; action = 0x0025; ui = $true; value = $true; label = 'Show window contents while dragging' }
  [void][OBWin]::SetBoolUi(0x0025, $false)
  Change 'Show window contents while dragging' 'On' 'Off'
} else { Same 'Show window contents while dragging' 'Off' }
[OBWin]::Broadcast('WindowMetrics')
Result -Summary 'Visual effects set for performance'
