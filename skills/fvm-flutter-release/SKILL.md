---
name: fvm-flutter-release
description: Use when initializing fvm in a Flutter project, pinning latest compatible Flutter SDK, or building and uploading to App Store and Google Play. Covers fvm setup workflow (SDK constraint matching), CLAUDE.md command migration, and fvm-aware dual-platform release scripts.
---

# FVM Flutter Release

## Overview

Pin Flutter SDK per-project with fvm, then build and upload to both App Store and Google Play using fvm-aware scripts.

## FVM Setup Workflow

### 1. Find Latest Compatible Version

```bash
# Check project SDK constraint
grep 'sdk:' pubspec.yaml
# e.g. sdk: ^3.10.7 → needs Dart >= 3.10.7

# List locally cached versions with Dart info
fvm list
```

Match rule: pick the **highest version number** whose Dart SDK satisfies pubspec constraint.

### 2. Pin Version

```bash
echo "y" | fvm use <version>
# Creates .fvmrc, adds .fvm/ to .gitignore
```

### 3. Update Project Commands

All `flutter`/`dart` commands become `fvm flutter`/`fvm dart`:

```bash
fvm flutter run
fvm flutter test
fvm flutter gen-l10n
fvm flutter build ipa --release
fvm flutter build appbundle --release
fvm dart run flutter_launcher_icons
```

**Update CLAUDE.md** to reflect `fvm` prefix — search-replace all `flutter` commands.

### 4. Verify

```bash
fvm flutter doctor
fvm flutter test
```

## Dual-Platform Release

### Quick Start

```bash
# Copy scripts to project
cp -r ~/.claude/skills/fvm-flutter-release/scripts/ ./scripts/
chmod +x scripts/*.sh

# iOS
export TEAM_ID=xxx CERT_HASH=xxx API_KEY=xxx API_ISSUER=xxx
export PROVISIONING_PROFILE="$HOME/Library/MobileDevice/Provisioning Profiles/xxx.mobileprovision"
./scripts/fvm_ios_upload.sh

# Android
./scripts/fvm_android_upload.sh [track]
# track: internal | alpha | beta | production (default: production)

# Both
./scripts/fvm_release_all.sh
```

### Environment Variables

| Variable | Platform | Description |
|----------|----------|-------------|
| `TEAM_ID` | iOS | Apple Developer Team ID |
| `CERT_HASH` | iOS | Distribution cert hash (`security find-identity -p codesigning`) |
| `PROVISIONING_PROFILE` | iOS | Path to .mobileprovision file |
| `API_KEY` | iOS | App Store Connect API Key ID |
| `API_ISSUER` | iOS | App Store Connect Issuer ID |
| `DART_DEFINES` | Both | Extra `--dart-define` flags (space-separated `KEY=VALUE` pairs) |

Android requires `android/key.properties` + `android/fastlane/` setup with service account JSON.

### Advanced Deployment

For Xcode 26.x `exportArchive` bug workaround, macOS, or Firebase web deploy, see skill `flutter-deploy`.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Using `flutter` instead of `fvm flutter` | Check `.fvmrc` exists → always prefix with `fvm` |
| Picking fvm version by Flutter number | Match by **Dart SDK** version against pubspec `sdk:` constraint |
| Forgetting `--dart-define` for release | Pass API keys via env vars, never hardcode |
| Uploading APK to Play Store | Always use `appbundle` (AAB) |

## Related skills

- **`release-preflight`** → **`flutter-verify`** → **`release-app`** → **`mobile-store-upload-cli`** — use fvm-flutter-release during the preflight and verify stages to build release artifacts with specific Flutter versions.
- **`flutter-pub-get-stuck`** — if flutter pub get hangs when using FVM, use this skill to diagnose the issue.
