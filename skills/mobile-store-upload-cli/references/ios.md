# iOS TestFlight Upload (CLI)

## Prereqs

- Xcode installed (Command Line Tools included).
- App exists in App Store Connect.
- Signing set up for the target bundle ID.
- Credentials:
  - Option A: Apple ID + app-specific password (App Store Connect).
  - Option B: App Store Connect API key (Key ID, Issuer ID, .p8 file).

## Variables

```
WORKSPACE="App.xcworkspace"
PROJECT="App.xcodeproj"
SCHEME="App"
CONFIGURATION="Release"
ARCHIVE_PATH="./build/App.xcarchive"
EXPORT_PATH="./build/export"
EXPORT_OPTIONS_PLIST="./ExportOptions.plist"
IPA_PATH="${EXPORT_PATH}/App.ipa"
APPLE_ID="user@example.com"
APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
API_KEY_ID="ABC123DEFG"
API_ISSUER_ID="11223344-5566-7788-99AA-BBCCDDEEFF00"
API_KEY_PATH="./AuthKey_ABC123DEFG.p8"
```

## Build and Export IPA

Use workspace OR project.

```
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  clean archive

xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
```

Minimal `ExportOptions.plist` for App Store/TestFlight:

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>YOUR_TEAM_ID</string>
</dict>
</plist>
```

## Validate and Upload

> **Note:** `xcrun altool` was deprecated by Apple in November 2023. Use `xcrun iTMSTransporter` instead.

Using App Store Connect API key (recommended):

```
xcrun iTMSTransporter -m upload \
  -f "$IPA_PATH" \
  -apiKey "$API_KEY_ID" \
  -apiIssuer "$API_ISSUER_ID"
```

Using Apple ID + app-specific password:

```
xcrun iTMSTransporter -m upload -assetFile "$IPA_PATH" -u "$APPLE_ID" -p "$APP_SPECIFIC_PASSWORD"
```

## Verify

- Check processing status in App Store Connect > TestFlight.
- Once processed, assign the build to a test group.
