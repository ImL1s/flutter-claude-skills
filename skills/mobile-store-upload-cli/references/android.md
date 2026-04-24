# Android Play Store Upload (CLI)

## Prereqs

- Android SDK + JDK + Gradle available.
- App created in Play Console.
- Google Play Developer API enabled.
- Service account JSON with Play Console access (Release Manager or Admin).

## Variables

```
PACKAGE_NAME="com.example.app"
AAB_PATH="app/build/outputs/bundle/release/app-release.aab"
SERVICE_ACCOUNT_JSON="./play-service-account.json"
TRACK="internal"
```

## Build AAB

```
./gradlew bundleRelease
```

## Upload with Fastlane (CLI)

Install fastlane if needed:

```
gem install fastlane
```

Upload the AAB:

```
fastlane supply \
  --aab "$AAB_PATH" \
  --package_name "$PACKAGE_NAME" \
  --track "$TRACK" \
  --json_key "$SERVICE_ACCOUNT_JSON" \
  --skip_upload_metadata true \
  --skip_upload_images true \
  --skip_upload_screenshots true
```

Optional: include release notes and metadata by providing a metadata directory:

```
fastlane supply \
  --aab "$AAB_PATH" \
  --package_name "$PACKAGE_NAME" \
  --track "$TRACK" \
  --json_key "$SERVICE_ACCOUNT_JSON" \
  --metadata_path "./fastlane/metadata"
```

## Verify

- Check Play Console > Release > Testing (or Production) for the upload.
- Confirm processing and rollout status.
