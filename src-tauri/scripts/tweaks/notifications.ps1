# Pop-up notifications off
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 0 'DWord' 'Pop-up notifications' @{ '0' = 'Off'; '1' = 'On'; 'default' = 'On' } | Out-Null
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 0 'DWord' 'Windows tips and suggestions' @{ '0' = 'Off'; '1' = 'On'; 'default' = 'On' } | Out-Null
Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0 'DWord' '"Finish setting up your device" prompts' @{ '0' = 'Off'; '1' = 'On'; 'default' = 'On' } | Out-Null
Result -Summary 'Notifications silenced'
