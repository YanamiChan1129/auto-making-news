# -*- coding: utf-8 -*-
# 每日新闻写作系统通知（Toast）。用法：
#   powershell -File tools\schedule\toast.ps1 -Title "完成" -Message "今日 10 篇已全部生成" -Level success
# Level: info / success / warn / error
param(
    [string]$Title = "每日新闻写作",
    [string]$Message = "",
    [ValidateSet("info", "success", "warn", "error")][string]$Level = "info"
)
$ErrorActionPreference = "Continue"

$appId = "NewsWriter.Daily"
$startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$lnkPath = Join-Path $startMenu "每日新闻写作.lnk"

# 注册 AUMID：在开始菜单放一个带 AppUserModelID 的快捷方式，Toast 才能弹出
function Ensure-AppId {
    if (Test-Path -LiteralPath $lnkPath) { return }
    $null = New-Item -ItemType Directory -Path $startMenu -Force
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($lnkPath)
    $sc.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    $sc.Arguments = "-NoProfile -Command exit"
    $sc.Description = "每日新闻写作通知入口"
    $sc.Save()

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class ToastHelper {
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    class ShellLink { }

    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszFile, int cch, IntPtr pfd, int fFlags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszName, int cch);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszDir, int cch);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszArgs, int cch);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
        void GetHotkey(out short pwHotkey);
        void SetHotkey(short wHotkey);
        void GetShowCmd(out int piShowCmd);
        void SetShowCmd(int iShowCmd);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder pszIconPath, int cch, out int piIcon);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, int dwReserved);
        void Resolve(IntPtr hwnd, int fFlags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }

    [ComImport, Guid("0000010B-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPersistFile {
        void GetClassID(out Guid pClassID);
        int IsDirty();
        void Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, int dwMode);
        void Save([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, [MarshalAs(UnmanagedType.Bool)] bool fRemember);
        void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);
        void GetCurFile([Out, MarshalAs(UnmanagedType.LPWStr)] System.Text.StringBuilder ppszFileName);
    }

    [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore {
        int GetCount(out uint cProps);
        int GetAt(uint iProp, out PROPERTYKEY pkey);
        int GetValue(ref PROPERTYKEY key, out PROPVARIANT pv);
        int SetValue(ref PROPERTYKEY key, ref PROPVARIANT pv);
        int Commit();
    }

    [StructLayout(LayoutKind.Sequential)]
    struct PROPERTYKEY { public Guid fmtid; public uint pid; }

    [StructLayout(LayoutKind.Explicit)]
    struct PROPVARIANT {
        [FieldOffset(0)] public ushort vt;
        [FieldOffset(8)] public IntPtr pointerValue;
    }

    public static void SetAppUserModelId(string lnkPath, string appId) {
        object o = new ShellLink();
        IPersistFile pf = (IPersistFile)o;
        pf.Load(lnkPath, 2);
        IPropertyStore store = (IPropertyStore)o;
        PROPERTYKEY key = new PROPERTYKEY();
        key.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");
        key.pid = 5;
        PROPVARIANT pv = new PROPVARIANT();
        pv.vt = 31;
        pv.pointerValue = Marshal.StringToCoTaskMemUni(appId);
        store.SetValue(ref key, ref pv);
        store.Commit();
    }
}
"@
    try {
        [ToastHelper]::SetAppUserModelId($lnkPath, $appId)
    } catch {
        Remove-Item -LiteralPath $lnkPath -Force -ErrorAction SilentlyContinue
    }
}

function Send-WinToast {
    param([string]$t, [string]$m)
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > $null
    $xml = '<toast><visual><binding template="ToastGeneric"><text>' + $t + '</text><text>' + $m + '</text></binding></visual></toast>'
    $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
    $doc.LoadXml($xml)
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId)
    $notifier.Show((New-Object Windows.UI.Notifications.ToastNotification $doc))
    return $true
}

function Send-Balloon {
    param([string]$t, [string]$m)
    Add-Type -AssemblyName System.Windows.Forms
    $icon = New-Object System.Drawing.Icon([System.Drawing.SystemIcons]::Information, 64, 64)
    $ni = New-Object System.Windows.Forms.NotifyIcon
    $ni.Icon = $icon
    $ni.Visible = $true
    $ni.Text = "每日新闻写作"
    $ni.ShowBalloonTip(10000, $t, $m, [System.Windows.Forms.ToolTipIcon]::Info)
    Start-Sleep -Seconds 12
    $ni.Dispose()
}

# 手机推送（可选）：tools\state\push_config.json 配置后生效
function Send-Push {
    param([string]$t, [string]$m)
    $cfgFile = Join-Path (Split-Path -Parent $PSScriptRoot) "state\push_config.json"
    if (-not (Test-Path -LiteralPath $cfgFile)) { return }
    try {
        $cfg = Get-Content -LiteralPath $cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.type -eq "bark" -and $cfg.key) {
            $base = if ($cfg.url) { $cfg.url } else { "https://api.day.app" }
            $uri = ("{0}/{1}/{2}/{3}" -f $base, $cfg.key, [Uri]::EscapeDataString($t), [Uri]::EscapeDataString($m))
            Invoke-RestMethod -Uri $uri -TimeoutSec 10 | Out-Null
        } elseif ($cfg.type -eq "serverchan" -and $cfg.key) {
            $body = @{ title = $t; desp = $m }
            Invoke-RestMethod -Uri ("https://sctapi.ftqq.com/{0}.send" -f $cfg.key) -Method Post -Body $body -TimeoutSec 10 | Out-Null
        }
    } catch { return }
}

$escTitle = $Title -replace "&", "&amp;" -replace "<", "&lt;" -replace ">", "&gt;"
$escMsg = $Message -replace "&", "&amp;" -replace "<", "&lt;" -replace ">", "&gt;"

Ensure-AppId
$ok = $false
if (Test-Path -LiteralPath $lnkPath) {
    try { $ok = Send-WinToast $escTitle $escMsg } catch { $ok = $false }
}
if (-not $ok) {
    Send-Balloon $Title $Message
}
Send-Push -t $Title -m $Message
