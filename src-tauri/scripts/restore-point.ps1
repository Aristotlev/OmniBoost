# System Restore point before any change
Step 'Creating a System Restore point'
Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0 'DWord' 'Restore point frequency limit' @{ '0' = 'None'; 'default' = '24 hours' } | Out-Null
$ok = $false
try {
  Checkpoint-Computer -Description 'Before OmniBoost' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
  $ok = $true
} catch {
  try {
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
    Info 'System Protection turned on for the system drive'
    Checkpoint-Computer -Description 'Before OmniBoost' -RestorePointType 'MODIFY_SETTINGS' -ErrorAction Stop
    $ok = $true
  } catch { Warn "Restore point not created: $($_.Exception.Message)" }
}
if ($ok) { Change 'System Restore point' 'None' 'Before OmniBoost'; Result -Summary 'Restore point created' }
else { Result -Status 'failed' -Summary 'No restore point. The OmniBoost undo journal is still active.' }
