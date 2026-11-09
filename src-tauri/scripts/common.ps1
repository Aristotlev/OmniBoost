# OmniBoost engine - shared helpers. Prepended to every script at runtime.
# Target: Windows PowerShell 5.1 (powershell.exe). Keep syntax 5.1 compatible and ASCII only.

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}

$OB_Root = Join-Path $env:ProgramData 'OmniBoost'
$OB_Backup = Join-Path $OB_Root 'backup.json'
if (-not (Test-Path -LiteralPath $OB_Root)) { New-Item -ItemType Directory -Path $OB_Root -Force | Out-Null }

$OB_Tweak = $env:OMNIBOOST_TWEAK
$OB_Options = New-Object PSObject
if ($env:OMNIBOOST_OPTIONS) { try { $OB_Options = $env:OMNIBOOST_OPTIONS | ConvertFrom-Json } catch {} }
$script:OB_Changes = 0

function Get-Opt([string]$Name, $Default) {
  if ($OB_Options -and ($OB_Options.PSObject.Properties.Name -contains $Name)) { return $OB_Options.$Name }
  return $Default
}

# ---------- protocol ----------
function Emit([string]$Kind, $Obj) {
  $json = ConvertTo-Json -InputObject $Obj -Compress -Depth 10
  [Console]::Out.WriteLine("@@$Kind $json")
  [Console]::Out.Flush()
}
function Step([string]$Msg, $Pct = $null) {
  $o = @{ msg = $Msg }
  if ($null -ne $Pct) { $o.pct = [int][math]::Max(0, [math]::Min(100, [double]$Pct)) }
  Emit 'STEP' $o
}
function Info([string]$Msg) { Emit 'INFO' @{ msg = $Msg } }
function Warn([string]$Msg) { Emit 'WARN' @{ msg = $Msg } }
function Change([string]$Target, $Before, $After, [string]$Path = '') {
  $script:OB_Changes++
  Emit 'CHANGE' @{ target = $Target; before = "$Before"; after = "$After"; path = $Path }
}
function Same([string]$Target, $Value, [string]$Path = '') { Emit 'SAME' @{ target = $Target; value = "$Value"; path = $Path } }
function Result {
  param([string]$Status = 'done', [string]$Summary = '', [bool]$Reboot = $false, [long]$Freed = 0, $Manual = @())
  $m = @()
  foreach ($x in @($Manual)) { if ($x) { $m += $x } }
  # A restart is only needed when this step actually changed something.
  $rb = [bool]($Reboot -and $script:OB_Changes -gt 0)
  Emit 'RESULT' @{ status = $Status; summary = $Summary; reboot = $rb; freedBytes = $Freed; changes = $script:OB_Changes; manual = $m }
}
function Manual([string]$Title, [string]$Detail, [string]$Open = '') {
  $o = @{ title = $Title; detail = $Detail }
  if ($Open) { $o.open = $Open }
  return $o
}

# ---------- backup journal ----------
function Get-Backup {
  $list = New-Object System.Collections.ArrayList
  if (Test-Path -LiteralPath $OB_Backup) {
    try {
      $raw = [System.IO.File]::ReadAllText($OB_Backup)
      if ($raw.Trim()) {
        $parsed = ConvertFrom-Json -InputObject $raw
        foreach ($e in $parsed) { [void]$list.Add($e) }
      }
    } catch {}
  }
  return ,$list
}
function Save-Backup($List) {
  $json = ConvertTo-Json -InputObject @($List.ToArray()) -Depth 10
  if ($List.Count -eq 0) { $json = '[]' }
  [System.IO.File]::WriteAllText($OB_Backup, $json, (New-Object System.Text.UTF8Encoding($false)))
}
function Add-Backup([hashtable]$Entry) {
  $list = Get-Backup
  foreach ($e in $list) { if ($e.key -eq $Entry.key) { return } }
  $Entry.tweak = $OB_Tweak
  $Entry.time = (Get-Date).ToString('s')
  [void]$list.Add((New-Object PSObject -Property $Entry))
  Save-Backup $list
}

# ---------- registry ----------
function Show-RegPath([string]$Path, [string]$Name) {
  $p = $Path -replace '^HKLM:\\', 'HKLM\' -replace '^HKCU:\\', 'HKCU\' -replace '^Registry::HKEY_USERS\\', 'HKU\'
  if ($Name) { return "$p\$Name" }
  return $p
}
function Ensure-RegKey([string]$Path) {
  if (Test-Path -LiteralPath $Path) { return }
  $parent = Split-Path -Path $Path -Parent
  if ($parent -and -not (Test-Path -LiteralPath $parent)) { Ensure-RegKey $parent }
  New-Item -Path $Path -Force | Out-Null
}
function Get-RegInfo([string]$Path, [string]$Name) {
  try {
    $key = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($key.GetValueNames() -contains $Name) {
      $kind = $key.GetValueKind($Name).ToString()
      $val = $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
      return @{ existed = $true; kind = $kind; value = $val }
    }
  } catch {}
  return @{ existed = $false; kind = $null; value = $null }
}
function Format-RegValue($Value, [string]$Kind) {
  if ($null -eq $Value) { return '(not set)' }
  if ($Kind -eq 'Binary') { return (($Value | ForEach-Object { '{0:X2}' -f $_ }) -join ' ') }
  if ($Kind -eq 'MultiString') { return (@($Value) -join '; ') }
  if ($Kind -eq 'DWord') { $u = [uint32]([int64]$Value -band 0xFFFFFFFFL); if ($u -gt 9) { return ('{0} (0x{0:X})' -f $u) } return "$u" }
  return "$Value"
}
function Get-RegSerial($Info) {
  if (-not $Info.existed) { return $null }
  if ($Info.kind -eq 'Binary') { return [Convert]::ToBase64String([byte[]]$Info.value) }
  if ($Info.kind -eq 'MultiString') { return @($Info.value) }
  return $Info.value
}
function Backup-Reg([string]$Path, [string]$Name) {
  $info = Get-RegInfo $Path $Name
  Add-Backup @{ type = 'reg'; key = "reg|$Path|$Name"; path = $Path; name = $Name; existed = $info.existed; kind = $info.kind; value = (Get-RegSerial $info) }
  return $info
}
function Test-RegEqual($Info, $Value, [string]$Type) {
  if (-not $Info.existed) { return $false }
  if ($Info.kind -ne $Type) { return $false }
  if ($Type -eq 'Binary') { return ([Convert]::ToBase64String([byte[]]$Info.value) -eq [Convert]::ToBase64String([byte[]]$Value)) }
  if ($Type -eq 'DWord' -or $Type -eq 'QWord') { return ([int64]$Info.value -eq [int64]$Value) }
  return ("$($Info.value)" -ceq "$Value")
}
# Set a registry value, journal the original, emit a live change line.
function Set-Reg {
  param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord', [string]$Label = '', [hashtable]$Map = $null)
  $regPath = Show-RegPath $Path $Name
  $target = if ($Label) { $Label } else { $regPath }
  try {
    $info = Get-RegInfo $Path $Name
    $v = $Value
    if ($Type -eq 'Binary') { $v = [byte[]]$Value }
    if ($Type -eq 'DWord') { $v = [int32]([int64]$Value) }
    $after = Format-RegValue $v $Type
    if ($Map -and $Map.ContainsKey("$v")) { $after = $Map["$v"] }
    if (Test-RegEqual $info $v $Type) { Same $target $after $regPath; return $true }
    Add-Backup @{ type = 'reg'; key = "reg|$Path|$Name"; path = $Path; name = $Name; existed = $info.existed; kind = $info.kind; value = (Get-RegSerial $info) }
    Ensure-RegKey $Path
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $v -PropertyType $Type -Force -ErrorAction Stop | Out-Null
    $before = '(not set)'
    if ($info.existed) {
      $before = Format-RegValue $info.value $info.kind
      if ($Map -and $Map.ContainsKey("$($info.value)")) { $before = $Map["$($info.value)"] }
    } elseif ($Map -and $Map.ContainsKey('default')) { $before = $Map['default'] }
    Change $target $before $after $regPath
    return $true
  } catch {
    Warn "Could not set $target : $($_.Exception.Message)"
    return $false
  }
}
function Restore-RegEntry($e) {
  $target = Show-RegPath $e.path $e.name
  try {
    $cur = Get-RegInfo $e.path $e.name
    $curText = if ($cur.existed) { Format-RegValue $cur.value $cur.kind } else { '(not set)' }
    if (-not $e.existed) {
      if ($cur.existed) { Remove-ItemProperty -LiteralPath $e.path -Name $e.name -Force -ErrorAction Stop; Change $target $curText '(removed)' }
      return
    }
    Ensure-RegKey $e.path
    $v = $e.value
    if ($e.kind -eq 'Binary') { $v = [Convert]::FromBase64String([string]$e.value) }
    elseif ($e.kind -eq 'DWord') { $v = [int32]([int64]$e.value) }
    elseif ($e.kind -eq 'QWord') { $v = [int64]$e.value }
    elseif ($e.kind -eq 'MultiString') { $v = [string[]]@($e.value) }
    New-ItemProperty -LiteralPath $e.path -Name $e.name -Value $v -PropertyType $e.kind -Force -ErrorAction Stop | Out-Null
    Change $target $curText (Format-RegValue $v $e.kind)
  } catch { Warn "Could not restore $target : $($_.Exception.Message)" }
}

# ---------- misc helpers ----------
function Format-Bytes([double]$B) {
  if ($B -ge 1GB) { return ('{0:N2} GB' -f ($B / 1GB)) }
  if ($B -ge 1MB) { return ('{0:N0} MB' -f ($B / 1MB)) }
  if ($B -ge 1KB) { return ('{0:N0} KB' -f ($B / 1KB)) }
  return ('{0:N0} B' -f $B)
}
function Get-FolderSize([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return 0 }
  $s = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
  if ($null -eq $s) { return 0 }
  return [long]$s
}
function Clear-Folder([string]$Path, [int]$OlderThanHours = 0, [string]$Label = '') {
  if (-not (Test-Path -LiteralPath $Path)) { return 0 }
  $before = Get-FolderSize $Path
  $cutoff = (Get-Date).AddHours(-$OlderThanHours)
  Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | ForEach-Object {
    if ($OlderThanHours -gt 0 -and $_.LastWriteTime -gt $cutoff) { return }
    try { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch {}
  }
  $after = Get-FolderSize $Path
  $freed = [long]($before - $after)
  if ($freed -lt 0) { $freed = 0 }
  $t = if ($Label) { $Label } else { $Path }
  if ($before -gt 0) {
    if ($freed -gt 0) { Change $t (Format-Bytes $before) (Format-Bytes $after) } else { Same $t ((Format-Bytes $before) + ' (in use)') }
  }
  return $freed
}
function Get-DriveFree([string]$Letter = 'C') {
  try { return [long](Get-PSDrive -Name $Letter -ErrorAction Stop).Free } catch { return 0 }
}
function Get-OSBuild {
  try { return [int](Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).BuildNumber } catch { return 0 }
}
# Apps OmniBoost never disables or stops: drivers, security, peripherals, anti-cheat, sync and VPN tools.
$OB_KeepRegex = '(?i)(SecurityHealth|Windows ?Defender|MsMpEng|Realtek|RtkAud|RTHDVCPL|Waves|MaxxAudio|Nahimic|Dolby|NVIDIA|NvBackend|nvcpl|\bAMD|Radeon|cncmd|Intel|igfx|IAStor|Logitech|LGHUB|LCore|Razer|Synapse|Corsair|iCUE|SteelSeries|HyperX|NGENUITY|Wooting|Glorious|Synaptics|\bELAN|ETDCtrl|ctfmon|Vanguard|vgtray|FACEIT|ESEA|OneDrive|Bitwarden|1Password|KeePass|NordVPN|ExpressVPN|ProtonVPN|WireGuard|OpenVPN|Tailscale|Afterburner|RTSS|RivaTuner|Armoury|\bASUS|Lenovo|Vantage|Alienware|\bDell\b|\bHP\b|OMEN|\bAcer\b|Thunderbolt|Bluetooth|Kaspersky|Bitdefender|Norton|Avast|\bAVG\b|ESET|Malwarebytes|McAfee|Sophos|Trend ?Micro|Webroot|Avira|OmniBoost|Touchpad|Precision|Wacom|Huion|XPPen|MSI ?Center|Dragon ?Center|Mystic|Gigabyte|RGB Fusion)'

# ---------- long-running work ----------
$OB_SkipFlag = Join-Path $OB_Root 'run\skip.flag'
# True once when the user pressed "Skip this step" in the app.
function Test-SkipRequested {
  if (Test-Path -LiteralPath $OB_SkipFlag) { Remove-Item -LiteralPath $OB_SkipFlag -Force -ErrorAction SilentlyContinue; return $true }
  return $false
}
function Format-Elapsed([TimeSpan]$T) {
  if ($T.TotalMinutes -ge 1) { return ('{0}m {1:00}s' -f [int][math]::Floor($T.TotalMinutes), $T.Seconds) }
  return ('{0}s' -f [int][math]::Floor($T.TotalSeconds))
}
function Stop-ProcessTree([int]$ProcessId) {
  & "$env:SystemRoot\System32\taskkill.exe" /T /F /PID $ProcessId 2>$null | Out-Null
}
function Get-SysDriveLetter { return $env:SystemDrive.TrimEnd(':') }
function Test-ProcessRunning([string[]]$Names) {
  foreach ($n in $Names) { if (Get-Process -Name $n -ErrorAction SilentlyContinue) { return $true } }
  return $false
}
# Launch something un-elevated through the shell (the app itself runs as admin).
function Start-Unelevated([string]$Target) {
  try { Start-Process -FilePath "$env:SystemRoot\explorer.exe" -ArgumentList "`"$Target`"" | Out-Null } catch {}
}
function Get-Hardware {
  $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '(?i)(basic display|remote display|virtual|parsec|meta|idd|spacedesk|citrix|vmware|hyper-v)' })
  $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
  return @{
    gpus = $gpus
    cpu = $cpu
    nvidia = [bool](@($gpus | Where-Object { $_.Name -match '(?i)nvidia' }).Count -gt 0) -and (Test-Path "$env:SystemRoot\System32\nvapi64.dll")
    amd = [bool](@($gpus | Where-Object { $_.Name -match '(?i)(amd|radeon)' }).Count -gt 0)
    battery = [bool](@(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue).Count -gt 0)
    x3dDual = [bool]($cpu -and $cpu.Name -match '(?i)(7950X3D|7900X3D|9950X3D|9900X3D)')
  }
}

# ---------- native helpers (compiled on demand) ----------
function Import-OBWin {
  if ('OBWin' -as [type]) { return }
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class OBWin {
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SystemParametersInfo(uint action, uint uiParam, IntPtr pvParam, uint fWinIni);
  [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
  public static bool GetBool(uint action) {
    IntPtr p = Marshal.AllocHGlobal(4);
    try { Marshal.WriteInt32(p, 0); SystemParametersInfo(action, 0, p, 0); return Marshal.ReadInt32(p) != 0; } finally { Marshal.FreeHGlobal(p); }
  }
  public static bool SetBool(uint action, bool v) { return SystemParametersInfo(action, 0, v ? new IntPtr(1) : IntPtr.Zero, 3); }
  public static bool SetBoolUi(uint action, bool v) { return SystemParametersInfo(action, v ? 1u : 0u, IntPtr.Zero, 3); }
  public static bool GetMinAnimate() {
    IntPtr p = Marshal.AllocHGlobal(8);
    try { Marshal.WriteInt32(p, 0, 8); Marshal.WriteInt32(p, 4, 0); SystemParametersInfo(0x0048, 8, p, 0); return Marshal.ReadInt32(p, 4) != 0; } finally { Marshal.FreeHGlobal(p); }
  }
  public static bool SetMinAnimate(bool v) {
    IntPtr p = Marshal.AllocHGlobal(8);
    try { Marshal.WriteInt32(p, 0, 8); Marshal.WriteInt32(p, 4, v ? 1 : 0); return SystemParametersInfo(0x0049, 8, p, 3); } finally { Marshal.FreeHGlobal(p); }
  }
  public static void Broadcast(string area) {
    UIntPtr r; SendMessageTimeout(new IntPtr(0xffff), 0x001A, UIntPtr.Zero, area, 0x0002, 3000, out r);
  }
}
'@
}

function Import-OBDisplay {
  if ('OBDisplay' -as [type]) { return }
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class OBDisplay {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName;
    public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra; public int dmFields;
    public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation; public int dmDisplayFixedOutput;
    public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName;
    public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight; public int dmDisplayFlags; public int dmDisplayFrequency;
    public int dmICMMethod; public int dmICMIntent; public int dmMediaType; public int dmDitherType; public int dmReserved1; public int dmReserved2; public int dmPanningWidth; public int dmPanningHeight;
  }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct DISPLAY_DEVICE {
    public int cb;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string DeviceName;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceString;
    public int StateFlags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceID;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string DeviceKey;
  }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE dd, uint flags);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplaySettings(string name, int mode, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int ChangeDisplaySettingsEx(string name, ref DEVMODE dm, IntPtr hwnd, uint flags, IntPtr lParam);
  static DEVMODE NewMode() { DEVMODE d = new DEVMODE(); d.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); return d; }

  // Each entry: device|monitorName|width|height|currentHz|maxHzAtCurrentRes|primary
  public static string[] List() {
    List<string> o = new List<string>();
    for (uint i = 0; i < 16; i++) {
      DISPLAY_DEVICE dd = new DISPLAY_DEVICE(); dd.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
      if (!EnumDisplayDevices(null, i, ref dd, 0)) break;
      if ((dd.StateFlags & 0x1) == 0) continue;
      DEVMODE cur = NewMode();
      if (!EnumDisplaySettings(dd.DeviceName, -1, ref cur)) continue;
      int max = cur.dmDisplayFrequency;
      DEVMODE m = NewMode();
      for (int k = 0; EnumDisplaySettings(dd.DeviceName, k, ref m); k++) {
        if (m.dmPelsWidth == cur.dmPelsWidth && m.dmPelsHeight == cur.dmPelsHeight && m.dmBitsPerPel == cur.dmBitsPerPel && (m.dmDisplayFlags & 0x2) == 0 && m.dmDisplayFrequency > max) max = m.dmDisplayFrequency;
        m = NewMode();
      }
      DISPLAY_DEVICE mon = new DISPLAY_DEVICE(); mon.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
      string monName = dd.DeviceString;
      if (EnumDisplayDevices(dd.DeviceName, 0, ref mon, 0) && !String.IsNullOrEmpty(mon.DeviceString)) monName = mon.DeviceString;
      bool primary = (dd.StateFlags & 0x4) != 0;
      o.Add(dd.DeviceName + "|" + monName + "|" + cur.dmPelsWidth + "|" + cur.dmPelsHeight + "|" + cur.dmDisplayFrequency + "|" + max + "|" + (primary ? "1" : "0"));
    }
    return o.ToArray();
  }
  // returns DISP_CHANGE code (0 = success)
  public static int SetFrequency(string device, int hz) {
    DEVMODE cur = NewMode();
    if (!EnumDisplaySettings(device, -1, ref cur)) return -100;
    cur.dmDisplayFrequency = hz;
    cur.dmFields = 0x400000;
    int t = ChangeDisplaySettingsEx(device, ref cur, IntPtr.Zero, 0x02, IntPtr.Zero);
    if (t != 0) return t;
    return ChangeDisplaySettingsEx(device, ref cur, IntPtr.Zero, 0x01, IntPtr.Zero);
  }
}
'@
}

function Import-OBNvDrs {
  if ('OBNvDrs' -as [type]) { return }
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class OBNvDrs {
  [DllImport("nvapi64.dll", EntryPoint="nvapi_QueryInterface", CallingConvention=CallingConvention.Cdecl)] static extern IntPtr QI(uint id);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DInit();
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DCreate(out IntPtr h);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DSession(IntPtr h);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DBase(IntPtr h, out IntPtr p);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DGet(IntPtr h, IntPtr p, uint id, IntPtr s);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DSet(IntPtr h, IntPtr p, IntPtr s);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DDel(IntPtr h, IntPtr p, uint id);
  const int SZ = 12320;            // sizeof(NVDRS_SETTING_V1)
  const int OFF_ID = 4100, OFF_TYPE = 4104, OFF_CUR = 8220;
  static Delegate F(uint id, Type t) { IntPtr p = QI(id); if (p == IntPtr.Zero) throw new Exception("NVAPI function 0x" + id.ToString("X8") + " not available"); return Marshal.GetDelegateForFunctionPointer(p, t); }
  static IntPtr NewSetting() { IntPtr b = Marshal.AllocHGlobal(SZ); Marshal.Copy(new byte[SZ], 0, b, SZ); Marshal.WriteInt32(b, 0, SZ | (1 << 16)); return b; }

  // mode: "set" applies values; "restore" sets values where restoreFlags[i]==1 and deletes where 0.
  // returns per setting: "id|existedBefore|valueBefore|status"
  public static string[] Run(uint[] ids, uint[] values, int[] keep) {
    string[] outp = new string[ids.Length];
    if (((DInit)F(0x0150E828, typeof(DInit)))() != 0) throw new Exception("NvAPI_Initialize failed");
    IntPtr h; if (((DCreate)F(0x0694D52E, typeof(DCreate)))(out h) != 0) throw new Exception("DRS session failed");
    try {
      if (((DSession)F(0x375DBD6B, typeof(DSession)))(h) != 0) throw new Exception("DRS load failed");
      IntPtr prof; if (((DBase)F(0xDA8466A0, typeof(DBase)))(h, out prof) != 0) throw new Exception("DRS base profile failed");
      DGet get = (DGet)F(0x73BF8338, typeof(DGet));
      DSet set = (DSet)F(0x577DD202, typeof(DSet));
      for (int i = 0; i < ids.Length; i++) {
        IntPtr g = NewSetting();
        int st = get(h, prof, ids[i], g);
        bool existed = st == 0;
        uint before = existed ? (uint)Marshal.ReadInt32(g, OFF_CUR) : 0;
        Marshal.FreeHGlobal(g);
        int r;
        if (keep != null && keep[i] == 0) {
          r = existed ? ((DDel)F(0xE4A26362, typeof(DDel)))(h, prof, ids[i]) : 0;
        } else {
          IntPtr s = NewSetting();
          Marshal.WriteInt32(s, OFF_ID, (int)ids[i]);
          Marshal.WriteInt32(s, OFF_TYPE, 0);
          Marshal.WriteInt32(s, OFF_CUR, (int)values[i]);
          r = set(h, prof, s);
          Marshal.FreeHGlobal(s);
        }
        outp[i] = ids[i] + "|" + (existed ? "1" : "0") + "|" + before + "|" + r;
      }
      if (((DSession)F(0xFCBC7E14, typeof(DSession)))(h) != 0) throw new Exception("DRS save failed");
    } finally { ((DSession)F(0xDAD9CFF8, typeof(DSession)))(h); }
    return outp;
  }
}
'@
}

function Import-OBPower {
  if ('OBPower' -as [type]) { return }
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class OBPower {
  [DllImport("powrprof.dll")] public static extern uint PowerSetActiveOverlayScheme(Guid g);
  [DllImport("powrprof.dll")] public static extern uint PowerGetEffectiveOverlayScheme(out Guid g);
  [DllImport("powrprof.dll")] static extern uint CallNtPowerInformation(int level, IntPtr inBuf, uint inLen, IntPtr outBuf, uint outLen);
  // SYSTEM_POWER_CAPABILITIES.AoAc (Modern Standby) is the BOOLEAN at offset 20
  public static bool IsModernStandby() {
    IntPtr b = Marshal.AllocHGlobal(256);
    try { Marshal.Copy(new byte[256], 0, b, 256); if (CallNtPowerInformation(4, IntPtr.Zero, 0, b, 256) != 0) return false; return Marshal.ReadByte(b, 20) != 0; }
    finally { Marshal.FreeHGlobal(b); }
  }
  public static string GetOverlay() { Guid g; if (PowerGetEffectiveOverlayScheme(out g) != 0) return ""; return g.ToString(); }
}
'@
}

function Import-OBMem {
  if ('OBMem' -as [type]) { return }
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class OBMem {
  [StructLayout(LayoutKind.Sequential, Pack=1)] struct TP { public int Count; public long Luid; public int Attr; }
  [DllImport("ntdll.dll")] static extern int NtSetSystemInformation(int cls, ref int info, int len);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr h, int access, out IntPtr tok);
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool LookupPrivilegeValue(string sys, string name, out long luid);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool AdjustTokenPrivileges(IntPtr tok, bool all, ref TP st, int len, IntPtr prev, IntPtr ret);
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  public static int PurgeStandby() {
    IntPtr tok;
    if (!OpenProcessToken(GetCurrentProcess(), 0x28, out tok)) return -1;
    long luid;
    if (!LookupPrivilegeValue(null, "SeProfileSingleProcessPrivilege", out luid)) return -2;
    TP tp = new TP(); tp.Count = 1; tp.Luid = luid; tp.Attr = 2;
    AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
    int cmd = 4; // MemoryPurgeStandbyList
    return NtSetSystemInformation(80, ref cmd, 4); // SystemMemoryListInformation
  }
}
'@
}

# ---------- powercfg helpers ----------
function Get-ActiveSchemeGuid {
  $o = (& powercfg /getactivescheme) -join ' '
  if ($o -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { return $Matches[1].ToLower() }
  return $null
}
function Get-SchemeName([string]$Guid) {
  foreach ($l in (& powercfg /list)) { if ($l -match [regex]::Escape($Guid) -and $l -match '\((.+?)\)') { return $Matches[1] } }
  return $Guid
}
# Returns AC index (int) of a power setting on a scheme, or $null
function Get-PowerAc([string]$Scheme, [string]$Sub, [string]$Setting) {
  $o = (& powercfg /q $Scheme $Sub $Setting 2>$null) -join "`n"
  $m = [regex]::Matches($o, '0x([0-9a-fA-F]{8})')
  if ($m.Count -ge 2) { return [Convert]::ToInt32($m[$m.Count - 2].Groups[1].Value, 16) }
  return $null
}

# ---------- game detection ----------
function Find-GameExe([string]$Dir) {
  if (-not $Dir -or -not (Test-Path -LiteralPath $Dir)) { return $null }
  $skip = '(?i)(unins|setup|install|redist|vcredist|vc_redist|dxsetup|crash|report|helper|updater|update|easyanticheat|battleye|beservice|prereq|dotnet|directx|cef|webhelper|7z|python|java|overlay|launcherpatcher|cleanup|benchmark)'
  $exes = @(Get-ChildItem -LiteralPath $Dir -Recurse -Depth 5 -Filter *.exe -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch $skip })
  if ($exes.Count -eq 0) { return $null }
  $ship = @($exes | Where-Object { $_.Name -match '(?i)-Shipping\.exe$' })
  if ($ship.Count -gt 0) { return ($ship | Sort-Object Length -Descending | Select-Object -First 1).FullName }
  return ($exes | Sort-Object Length -Descending | Select-Object -First 1).FullName
}
function Get-Games([int]$Max = 12) {
  $games = @()
  # Steam
  try {
    $steam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
    if ($steam) {
      $steam = $steam -replace '/', '\'
      $libs = @($steam)
      $lf = Join-Path $steam 'steamapps\libraryfolders.vdf'
      if (Test-Path -LiteralPath $lf) {
        foreach ($m in [regex]::Matches([IO.File]::ReadAllText($lf), '"path"\s+"([^"]+)"')) { $libs += ($m.Groups[1].Value -replace '\\\\', '\') }
      }
      $playtime = @{}
      foreach ($cfg in @(Get-ChildItem -Path (Join-Path $steam 'userdata\*\config\localconfig.vdf') -ErrorAction SilentlyContinue)) {
        $txt = [IO.File]::ReadAllText($cfg.FullName)
        foreach ($m in [regex]::Matches($txt, '"(\d{2,})"\s*\{(?:(?!"\d{2,}"\s*\{).){0,4000}?"Playtime"\s*"(\d+)"', 'Singleline')) {
          $id = $m.Groups[1].Value; $pt = [int]$m.Groups[2].Value
          if (-not $playtime.ContainsKey($id) -or $playtime[$id] -lt $pt) { $playtime[$id] = $pt }
        }
      }
      $skipIds = @('228980', '1070560', '1391110', '1628350', '1493710', '250820', '431960')
      foreach ($lib in ($libs | Select-Object -Unique)) {
        foreach ($acf in @(Get-ChildItem -Path (Join-Path $lib 'steamapps\appmanifest_*.acf') -ErrorAction SilentlyContinue)) {
          $t = [IO.File]::ReadAllText($acf.FullName)
          $id = if ($t -match '"appid"\s+"(\d+)"') { $Matches[1] } else { '' }
          if ($skipIds -contains $id) { continue }
          $name = if ($t -match '"name"\s+"([^"]+)"') { $Matches[1] } else { '' }
          $dir = if ($t -match '"installdir"\s+"([^"]+)"') { Join-Path $lib ('steamapps\common\' + $Matches[1]) } else { '' }
          if ($name -match '(?i)(redistributable|proton|runtime|soundtrack|dedicated server|sdk)') { continue }
          $pt = 0; if ($playtime.ContainsKey($id)) { $pt = $playtime[$id] }
          $games += New-Object PSObject -Property @{ name = $name; dir = $dir; source = 'Steam'; playtime = $pt; exe = $null }
        }
      }
    }
  } catch {}
  # Epic
  try {
    foreach ($item in @(Get-ChildItem -Path "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests\*.item" -ErrorAction SilentlyContinue)) {
      $j = Get-Content -LiteralPath $item.FullName -Raw | ConvertFrom-Json
      if ($j.bIsApplication -eq $false) { continue }
      if ($j.AppCategories -and -not (@($j.AppCategories) -contains 'games')) { continue }
      $exe = $null
      if ($j.LaunchExecutable) { $exe = Join-Path $j.InstallLocation $j.LaunchExecutable }
      $games += New-Object PSObject -Property @{ name = $j.DisplayName; dir = $j.InstallLocation; source = 'Epic'; playtime = 0; exe = $exe }
    }
  } catch {}
  # Riot
  try {
    foreach ($y in @(Get-ChildItem -Path "$env:ProgramData\Riot Games\Metadata\*\*.product_settings.yaml" -ErrorAction SilentlyContinue)) {
      $t = [IO.File]::ReadAllText($y.FullName)
      if ($t -match 'product_install_full_path:\s*"?([^"\r\n]+)"?') {
        $dir = $Matches[1] -replace '/', '\'
        $nm = if ($y.Name -match '^valorant') { 'VALORANT' } elseif ($y.Name -match '^league') { 'League of Legends' } else { ($y.BaseName -split '\.')[0] }
        if ($y.Name -match '^riot_client') { continue }
        $games += New-Object PSObject -Property @{ name = $nm; dir = $dir; source = 'Riot'; playtime = 0; exe = $null }
      }
    }
  } catch {}
  $out = @()
  foreach ($g in ($games | Sort-Object -Property playtime -Descending)) {
    if ($out.Count -ge $Max) { break }
    $exe = $g.exe
    if ($exe -and (Test-Path -LiteralPath $exe)) {
      $deep = Find-GameExe $g.dir
      if ($deep -and $deep -match '(?i)-Shipping\.exe$') { $exe = $deep }
    } else { $exe = Find-GameExe $g.dir }
    if (-not $exe) { continue }
    $out += @{ name = $g.name; exe = $exe; source = $g.source; playtimeMin = [int]$g.playtime }
  }
  return ,$out
}
