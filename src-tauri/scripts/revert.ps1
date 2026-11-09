# OmniBoost undo. Replays the backup journal in reverse order.
$list = Get-Backup
if ($list.Count -eq 0) { Info 'Nothing to undo.'; Result -Status 'skipped' -Summary 'No saved changes found'; return }
Info "Restoring $($list.Count) saved settings"
$reboot = $false
$items = $list.ToArray()
[array]::Reverse($items)
$nvIds = @(); $nvVals = @(); $nvKeep = @()

foreach ($e in $items) {
  switch ($e.type) {
    'reg' {
      Restore-RegEntry $e
      if ($e.path -match '(GraphicsDrivers|DeviceGuard|PriorityControl|Tcpip)') { $reboot = $true }
    }
    'powerscheme' {
      $cur = Get-ActiveSchemeGuid
      & powercfg /setactive $e.guid | Out-Null
      Change 'Power plan' (Get-SchemeName $cur) (Get-SchemeName $e.guid)
      if ($e.created) { & powercfg /delete $e.created 2>$null | Out-Null; Info "Removed the OmniBoost power plan" }
    }
    'overlay' {
      try { Import-OBPower; [void][OBPower]::PowerSetActiveOverlayScheme([Guid]$e.guid); Change 'Power mode' 'Best performance' $e.label } catch { Warn "Power mode restore failed: $($_.Exception.Message)" }
    }
    'service' {
      try {
        $st = switch ($e.startMode) { 'Auto' { 'Automatic' } 'Manual' { 'Manual' } 'Disabled' { 'Disabled' } default { $null } }
        if ($st) {
          Set-Service -Name $e.name -StartupType $st -ErrorAction Stop
          if ($e.delayed) { & sc.exe config $e.name start= delayed-auto | Out-Null }
          Change "Service $($e.name)" 'Manual' $e.startMode
        }
      } catch { Warn "Service $($e.name): $($_.Exception.Message)" }
    }
    'file' {
      try {
        if ($e.existed) { [IO.File]::WriteAllBytes($e.path, [Convert]::FromBase64String($e.content)); Change $e.path 'modified' 'restored' }
        elseif (Test-Path -LiteralPath $e.path) { Remove-Item -LiteralPath $e.path -Force; Change $e.path 'created' 'removed' }
      } catch { Warn "File $($e.path): $($_.Exception.Message)" }
    }
    'display' {
      try { Import-OBDisplay; $r = [OBDisplay]::SetFrequency($e.device, [int]$e.hz); if ($r -eq 0) { Change "$($e.name) refresh rate" "$($e.newHz) Hz" "$($e.hz) Hz" } else { Warn "Display restore code $r" } } catch { Warn $_.Exception.Message }
    }
    'spi' {
      try { Import-OBWin; if ($e.ui) { [void][OBWin]::SetBoolUi([uint32]$e.action, [bool]$e.value) } elseif ($e.anim) { [void][OBWin]::SetMinAnimate([bool]$e.value) } else { [void][OBWin]::SetBool([uint32]$e.action, [bool]$e.value) }; Change $e.label 'Off' $(if ($e.value) { 'On' } else { 'Off' }) } catch {}
    }
    'netadv' {
      try { Set-NetAdapterAdvancedProperty -Name $e.adapter -RegistryKeyword $e.keyword -RegistryValue $e.value -ErrorAction Stop; Change "$($e.adapter): $($e.label)" $e.newLabel 'restored' } catch { Warn "$($e.adapter): $($_.Exception.Message)" }
    }
    'cmd' {
      try { & cmd.exe /c $e.revert | Out-Null; Change $e.label 'changed' 'restored'; if ($e.reboot) { $reboot = $true } } catch {}
    }
    'task' {
      try { Enable-ScheduledTask -TaskPath $e.taskPath -TaskName $e.taskName -ErrorAction Stop | Out-Null; Change "Task: $($e.taskName)" 'Disabled' 'Enabled' } catch { Warn "Task $($e.taskName): $($_.Exception.Message)" }
    }
    'nvdrs' {
      $nvIds += [uint32]$e.settingId; $nvVals += [uint32]$e.value; $nvKeep += $(if ($e.existed) { 1 } else { 0 })
    }
    'pagefile' {
      try {
        $cs = Get-CimInstance Win32_ComputerSystem
        Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false } -ErrorAction Stop
        foreach ($f in @($e.files)) { New-CimInstance -ClassName Win32_PageFileSetting -Property @{ Name = $f.name; InitialSize = [uint32]$f.initial; MaximumSize = [uint32]$f.max } -ErrorAction SilentlyContinue | Out-Null }
        Change 'Page file' 'System managed' 'Custom (restored)'; $reboot = $true
      } catch { Warn $_.Exception.Message }
    }
  }
}
if ($nvIds.Count -gt 0) {
  try {
    Import-OBNvDrs
    $res = [OBNvDrs]::Run([uint32[]]$nvIds, [uint32[]]$nvVals, [int[]]$nvKeep)
    Change 'NVIDIA global profile' 'OmniBoost' 'restored'
  } catch { Warn "NVIDIA restore: $($_.Exception.Message)" }
}
$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
Move-Item -LiteralPath $OB_Backup -Destination (Join-Path $OB_Root "backup-undone-$stamp.json") -Force
Result -Status 'done' -Summary 'All OmniBoost changes were undone' -Reboot $reboot
