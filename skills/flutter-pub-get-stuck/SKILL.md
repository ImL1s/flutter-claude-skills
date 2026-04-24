---
name: flutter-pub-get-stuck
description: Diagnose and fix flutter pub get hanging, flutter build stuck, or any Flutter CLI command that hangs with zero output on Windows. Also covers "Can't load Kernel binary Invalid SDK hash" errors. Triggers on keywords like "pub get stuck", "pub get 卡住", "flutter hangs", "flutter build 卡住", "dart zombie", "flutter 卡", "pub get timeout", "flutter process cleanup", "Invalid SDK hash", "Can't load Kernel binary", "flutter build no output".
---

# Flutter CLI Stuck / Hangs / Invalid SDK Hash — Diagnosis & Fix

## When to Use

Use this skill when:
- `flutter pub get`, `flutter build`, `flutter run`, or ANY Flutter CLI command hangs indefinitely (no output for > 30 seconds)
- You see `Can't load Kernel binary: Invalid SDK hash` error
- `fvm flutter` commands produce zero output
- Flutter commands were working before but suddenly stopped

## Root Cause Checklist

Work through these **in order** — each step resolves a progressively deeper issue.

### 1. 🧟 Zombie dart.exe / java.exe Processes (Most Common)

**Symptoms:** Flutter command shows no output, or hangs at "Resolving dependencies..."

**Diagnosis:**
```powershell
Get-Process -Name dart,flutter,java -ErrorAction SilentlyContinue | Format-Table Name,Id,CPU,WS -AutoSize
```

**Key Indicators:**
- More than 5 dart.exe processes → likely zombies
- Any dart.exe using > 200MB memory (WS column) → stuck analysis/compilation
- java.exe running > 500MB → Gradle daemon holding resources
- A `flutter run` running for hours in another terminal → WILL block everything
- IDE analysis server constantly respawning dart.exe → kill IDE too

**Fix:**
```powershell
# Kill all Flutter-related processes
Get-Process dart,java,flutter -ea 0 | Stop-Process -Force -ea 0
Start-Sleep 2
# Verify zero remaining
Get-Process dart,java -ea 0 | Measure-Object | Select-Object -ExpandProperty Count
```

> [!WARNING]
> The IDE (VS Code / Android Studio) analysis server will **respawn** dart.exe processes. If zombies keep coming back, close the IDE first.

### 2. 🔒 Flutter SDK Lockfile

**Symptoms:** Zero output from any Flutter command. Zombie processes already killed but still hangs.

**Diagnosis & Fix:**

For FVM projects, first find the SDK path:
```powershell
# Read .fvmrc to find the Flutter version
Get-Content .fvmrc
# Common FVM paths on Windows:
#   C:\Users\<USER>\fvm\versions\<version>\
#   C:\Users\<USER>\AppData\Local\fvm\versions\<version>\
```

Then remove the lockfile:
```powershell
$sdkCache = "C:\Users\$env:USERNAME\fvm\versions\<VERSION>\bin\cache"
Remove-Item "$sdkCache\lockfile" -Force -ErrorAction SilentlyContinue
Remove-Item "$sdkCache\flutter.bat.lock" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:LOCALAPPDATA\Pub\Cache\lock" -Force -ErrorAction SilentlyContinue
```

### 3. 💀 Corrupted bin/cache — "Invalid SDK Hash" (Nuclear Option)

**Symptoms:**
- `Can't load Kernel binary: Invalid SDK hash` error
- Flutter commands hang even after killing processes and removing lockfiles
- `dart.exe --version` works but `flutter --version` hangs
- Deleting just the snapshot or lockfile doesn't help

**Root Cause:** The Dart SDK cached inside `bin/cache/dart-sdk/` is mismatched with the Flutter SDK version, or the `flutter_tools.snapshot` is corrupted. This typically happens after:
- Interrupted `flutter upgrade`
- Multiple FVM version switches
- Disk space issues during SDK download
- System crashes during Flutter operations

**Fix — Delete entire bin/cache:**
```powershell
# Step 1: Kill ALL dart/java processes
Get-Process dart,java,flutter -ea 0 | Stop-Process -Force -ea 0
Start-Sleep 2

# Step 2: Delete the entire bin/cache directory
$sdkPath = "C:\Users\$env:USERNAME\fvm\versions\<VERSION>"
cmd /c "rd /s /q $sdkPath\bin\cache"
# If rd fails on locked files, kill cmd.exe processes holding locks:
# Get-Process cmd -ea 0 | Stop-Process -Force -ea 0
# Then retry rd

# Step 3: Verify deletion
Test-Path "$sdkPath\bin\cache"  # Should return False

# Step 4: Reactivate FVM (fixes FVM's own snapshot mismatch)
& "$sdkPath\bin\cache\dart-sdk\bin\dart.exe" pub global deactivate fvm
& "$sdkPath\bin\cache\dart-sdk\bin\dart.exe" pub global activate fvm
# If dart.exe doesn't exist yet (cache deleted), use system dart:
# dart pub global deactivate fvm; dart pub global activate fvm

# Step 5: Run flutter doctor to trigger fresh SDK download
fvm flutter doctor -v
# This will:
#   - Download Dart SDK from Flutter engine
#   - Expand archive
#   - Build flutter_tools
#   - Run pub upgrade
```

> [!IMPORTANT]
> `Remove-Item -Recurse` in PowerShell often **silently fails** on locked files. Always use `cmd /c "rd /s /q <path>"` for reliable recursive deletion, and verify with `Test-Path` afterward.

> [!IMPORTANT]
> After deleting `bin/cache`, Flutter will re-download ~200MB of Dart SDK. Make sure you have internet connectivity. The first `flutter doctor` after cache deletion takes 2-5 minutes.

### 4. 📡 Network Issues (pub.dev unreachable)

**Diagnosis:**
```powershell
ping pub.dev -n 3
Invoke-WebRequest -Uri "https://pub.dev" -UseBasicParsing -TimeoutSec 5
```

**Fix:**
```powershell
# Use Chinese mirror if behind firewall
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
flutter pub get
```

### 5. 🧹 Corrupted Pub Cache

**Fix:**
```powershell
flutter clean
Remove-Item pubspec.lock -ErrorAction SilentlyContinue
flutter pub cache repair
flutter pub get
```

## One-Liner Emergency Fix

```powershell
# Kill everything → delete locks → clean → retry
Get-Process dart,java,flutter -ea 0 | Stop-Process -Force; Start-Sleep 2; Remove-Item pubspec.lock -ea 0; fvm flutter clean; fvm flutter pub get
```

## Nuclear One-Liner (when Invalid SDK hash)

```powershell
# Kill everything → nuke cache → reactivate FVM → rebuild
Get-Process dart,java -ea 0 | Stop-Process -Force; Start-Sleep 2; cmd /c "rd /s /q C:\Users\%USERNAME%\fvm\versions\<VERSION>\bin\cache"; dart pub global deactivate fvm; dart pub global activate fvm; fvm flutter doctor -v
```

## Finding the FVM SDK Path

The FVM SDK path varies across machines. To find it programmatically:

```powershell
# Method 1: Check where fvm.bat is located
where.exe fvm
# Usually: C:\Users\<USER>\AppData\Local\Pub\Cache\bin\fvm.bat

# Method 2: Look for flutter.bat in the user's fvm directory
Get-ChildItem "C:\Users\$env:USERNAME\fvm\versions" -Filter "flutter.bat" -Recurse -Depth 3 -ea 0 | Select-Object -First 5 -ExpandProperty FullName

# Method 3: Common locations
# C:\Users\<USER>\fvm\versions\<VERSION>\bin\flutter.bat
# C:\Users\<USER>\AppData\Local\fvm\versions\<VERSION>\bin\flutter.bat
```

## Prevention

1. **Always stop `flutter run` before running `flutter pub get`** — a hot-reloading session locks Dart processes
2. **Don't run multiple Flutter CLI commands simultaneously** in different terminals
3. **Close IDE before major cleanup operations** — the analysis server respawns dart.exe
4. **Check for zombie processes** if your machine feels slow or after IDE crashes
5. **Don't interrupt `flutter upgrade`** — if you must, delete `bin/cache` afterward
6. **When using FVM, stick to one version per terminal session** — rapid version switching can corrupt the cache
