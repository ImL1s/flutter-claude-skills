---
name: flutter-windows-ui-testing
description: Automate testing of Flutter Windows desktop apps via Win32 API (user32.dll). Use when visually verifying Flutter desktop UI — clicking buttons, opening popups, navigating pages, taking screenshots. Triggers on keywords like "test Windows app", "UI test desktop", "click Flutter window", "Windows 桌面測試", "自動化測試", "截圖驗證", "visual verification desktop".
---

# Flutter Windows Desktop UI Testing via Win32 API

## Overview

Flutter desktop apps on Windows render everything inside a single `FLUTTERVIEW` pane — the Windows UI Automation accessibility tree only exposes this single element. Therefore, **coordinate-based automation** via `user32.dll` is the practical approach.

## Architecture

```
PowerShell Script
    ├── Add-Type (C# interop for user32.dll)
    ├── Process → MainWindowHandle (HWND)
    ├── Focus: AttachThreadInput + BringWindowToTop + SetForegroundWindow
    ├── Coordinates: GetClientRect + ClientToScreen (excludes title bar)
    ├── Click: SetCursorPos + mouse_event
    ├── Key: keybd_event
    └── Screenshot: System.Drawing.Graphics.CopyFromScreen
```

## Critical Patterns

### 1. Getting Window Focus (MANDATORY)

Regular `SetForegroundWindow` **fails** when called from a background terminal. You MUST use `AttachThreadInput` to steal focus:

```powershell
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Threading;
public class FlutterTest {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte sc, uint f, UIntPtr e);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; }

    public static bool Focus(IntPtr h) {
        IntPtr fg = GetForegroundWindow();
        uint ft = GetWindowThreadProcessId(fg, out uint fp);
        uint mt = GetCurrentThreadId();
        if (ft != mt) AttachThreadInput(mt, ft, true);
        ShowWindow(h, 5); // SW_SHOW
        BringWindowToTop(h);
        bool r = SetForegroundWindow(h);
        if (ft != mt) AttachThreadInput(mt, ft, false);
        return r;
    }

    public static void Click(int x, int y) {
        SetCursorPos(x, y);
        Thread.Sleep(100);
        mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero); // MOUSEEVENTF_LEFTDOWN
        Thread.Sleep(50);
        mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero); // MOUSEEVENTF_LEFTUP
    }

    public static void Key(byte vk) {
        keybd_event(vk, 0, 0, UIntPtr.Zero);
        Thread.Sleep(30);
        keybd_event(vk, 0, 2, UIntPtr.Zero); // KEYEVENTF_KEYUP
    }
}
"@
```

### 2. Getting Client Area Coordinates

Flutter borderless windows have a 1px title bar. **Always use client-relative coordinates** to avoid offset errors:

```powershell
$p = Get-Process -Name "your_app" -ErrorAction SilentlyContinue | Select-Object -First 1
$hwnd = $p.MainWindowHandle

# Get client area origin and size (excludes title bar)
$origin = New-Object FlutterTest+POINT; $origin.X = 0; $origin.Y = 0
[FlutterTest]::ClientToScreen($hwnd, [ref]$origin)
$clientRect = New-Object FlutterTest+RECT
[FlutterTest]::GetClientRect($hwnd, [ref]$clientRect)
$cx = $origin.X; $cy = $origin.Y
$cw = $clientRect.R; $ch = $clientRect.B
```

### 3. Click at Relative Position

```powershell
function ClickRel([double]$relX, [double]$relY, [string]$desc) {
    $absX = $cx + [int]($cw * $relX)
    $absY = $cy + [int]($ch * $relY)
    Write-Host "  Click '$desc' at ($absX,$absY)"
    [FlutterTest]::Click($absX, $absY)
    Start-Sleep -Milliseconds 500
}
```

### 4. Take Window-Only Screenshot

```powershell
Add-Type -AssemblyName System.Drawing

function TakeScreenshot($name) {
    Start-Sleep -Milliseconds 600
    $bmp = New-Object System.Drawing.Bitmap($cw, $ch)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($cx, $cy, 0, 0, (New-Object System.Drawing.Size($cw, $ch)))
    $path = "/path/to/output/$name.png"
    $bmp.Save($path)
    $g.Dispose(); $bmp.Dispose()
    Write-Host "  => $name.png"
}
```

### 5. Dismiss Dialogs

```powershell
function PressEscape { [FlutterTest]::Key(0x1B); Start-Sleep -Milliseconds 400 }
# Dismiss paywall/dialog on launch:
PressEscape; PressEscape; PressEscape
```

## Coordinate Mapping Workflow

Since we can't inspect Flutter's widget tree from Win32, use this iterative approach:

1. **Take a screenshot first** — capture the client area to see the layout
2. **Estimate coordinates** from the screenshot (e.g., button at pixel 170,180 in a 459×841 window = relX 0.37, relY 0.21)
3. **Click and screenshot** — verify if the click landed correctly
4. **Adjust coordinates** if the test shows incorrect position (popup didn't open, wrong page navigation)

## Common Coordinate References (Voxboard 459×841)

| Element | relX | relY | Notes |
|---------|------|------|-------|
| Title bar back arrow | 0.08 | 0.03 | Top-left |
| Settings gear | 0.93 | 0.03 | Top-right |
| Mode tabs (聽寫) | 0.15 | 0.14 | First tab |
| STT chip | 0.37 | 0.21 | Whisper chip |
| LLM chip | 0.68 | 0.21 | LlamaCpp chip |
| Mic button | 0.50 | 0.88 | Center bottom |

## Key VK Codes

| Key | VK Code | Usage |
|-----|---------|-------|
| Escape | `0x1B` | Dismiss dialogs/popups |
| Enter | `0x0D` | Confirm |
| Back | `0x08` | Backspace |
| Tab | `0x09` | Navigate |

## Gotchas

1. **`SetForegroundWindow` returns False** from background processes — MUST use `AttachThreadInput` trick
2. **Flutter borderless windows** — title bar is 1px, use `GetClientRect` + `ClientToScreen`
3. **Screenshot captures wrong window** — always call `Focus()` before `CopyFromScreen`
4. **Windows UI Automation tree is useless** for Flutter — only exposes `FLUTTERVIEW` pane
5. **Popup menus render outside the window rect** — screenshot the full screen if popup extends beyond window bounds
6. **DPI scaling** — coordinates may be off on high-DPI screens, ensure your PowerShell process is DPI-aware

## Full Test Flow Example

```powershell
# 1. Launch app
taskkill /IM myapp.exe /F 2>$null
Start-Process "path\to\myapp.exe"
Start-Sleep -Seconds 5

# 2. Get handle and focus
$p = Get-Process -Name myapp | Select -First 1
$hwnd = $p.MainWindowHandle
[FlutterTest]::Focus($hwnd)

# 3. Get client coordinates
# ... (see section 2 above)

# 4. Dismiss paywall
PressEscape; PressEscape; PressEscape

# 5. Test flow
TakeScreenshot "01_main_page"
ClickRel 0.37 0.21 "stt-chip"     # Open STT popup
TakeScreenshot "02_stt_popup"
ClickRel 0.37 0.31 "select-model"  # Select 2nd model
TakeScreenshot "03_after_select"
PressEscape
ClickRel 0.93 0.03 "settings"      # Navigate to settings
TakeScreenshot "04_settings"
```
