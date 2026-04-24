#!/bin/bash
# =============================================================================
# iOS App Store Upload (fvm-aware)
# Bypasses Xcode 26.x exportArchive bug with manual IPA + codesign
#
# Required env vars:
#   TEAM_ID, CERT_HASH, PROVISIONING_PROFILE, API_KEY, API_ISSUER
# Optional:
#   DART_DEFINES  - space-separated KEY=VALUE pairs for --dart-define
#   PROJECT_ROOT  - project directory (default: pwd)
# =============================================================================

set -euo pipefail

: "${TEAM_ID:?Set TEAM_ID}"
: "${CERT_HASH:?Set CERT_HASH}"
: "${PROVISIONING_PROFILE:?Set PROVISIONING_PROFILE}"
: "${API_KEY:?Set API_KEY}"
: "${API_ISSUER:?Set API_ISSUER}"

PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
BUILD_DIR="/tmp/ios_build_$$"
trap "rm -rf $BUILD_DIR" EXIT

# Detect fvm
FLUTTER="flutter"
if [ -f "$PROJECT_ROOT/.fvmrc" ] && command -v fvm &>/dev/null; then
    FLUTTER="fvm flutter"
    echo ">>> Using fvm: $(fvm flutter --version | head -1)"
fi

# Build dart-define flags
DEFINE_FLAGS=""
for kv in ${DART_DEFINES:-}; do
    DEFINE_FLAGS="$DEFINE_FLAGS --dart-define=$kv"
done

echo ">>> [1/6] Flutter build..."
$FLUTTER build ios --release --no-codesign $DEFINE_FLAGS

echo ">>> [2/6] Xcode archive..."
cd "$PROJECT_ROOT/ios"
xcodebuild -workspace Runner.xcworkspace \
    -scheme Runner \
    -configuration Release \
    -archivePath "$BUILD_DIR/Runner.xcarchive" \
    -destination 'generic/platform=iOS' \
    CODE_SIGNING_ALLOWED=NO \
    archive
cd "$PROJECT_ROOT"

[ -d "$BUILD_DIR/Runner.xcarchive" ] || { echo "ERROR: Archive failed"; exit 1; }

echo ">>> [3/6] Build IPA structure..."
mkdir -p "$BUILD_DIR/ipa/Payload"
cp -R "$BUILD_DIR/Runner.xcarchive/Products/Applications/Runner.app" "$BUILD_DIR/ipa/Payload/"

if [ -d "$BUILD_DIR/Runner.xcarchive/SwiftSupport" ] && \
   [ "$(ls -A "$BUILD_DIR/Runner.xcarchive/SwiftSupport/iphoneos" 2>/dev/null)" ]; then
    cp -R "$BUILD_DIR/Runner.xcarchive/SwiftSupport" "$BUILD_DIR/ipa/"
fi

cp "$PROVISIONING_PROFILE" "$BUILD_DIR/ipa/Payload/Runner.app/embedded.mobileprovision"

echo ">>> [4/6] Codesign..."
APP_PATH="$BUILD_DIR/ipa/Payload/Runner.app"

security cms -D -i "$APP_PATH/embedded.mobileprovision" 2>/dev/null | \
    plutil -extract Entitlements xml1 -o "$BUILD_DIR/entitlements.plist" -

shopt -s nullglob
for fw in "$APP_PATH/Frameworks/"*.framework; do
    codesign -f -s "$CERT_HASH" "$fw" 2>/dev/null || true
done
for dl in "$APP_PATH/Frameworks/"*.dylib; do
    codesign -f -s "$CERT_HASH" "$dl" 2>/dev/null || true
done
if [ -d "$APP_PATH/PlugIns" ]; then
    for px in "$APP_PATH/PlugIns/"*.appex; do
        codesign -f -s "$CERT_HASH" "$px" 2>/dev/null || true
    done
fi
shopt -u nullglob

codesign -f -s "$CERT_HASH" --entitlements "$BUILD_DIR/entitlements.plist" "$APP_PATH"
codesign -vv "$APP_PATH" 2>&1 | grep -q "valid on disk" || { echo "ERROR: Codesign verify failed"; exit 1; }

echo ">>> [5/6] Package IPA..."
cd "$BUILD_DIR/ipa"
if [ -d "SwiftSupport" ]; then
    zip -qr "$BUILD_DIR/Runner.ipa" Payload SwiftSupport
else
    zip -qr "$BUILD_DIR/Runner.ipa" Payload
fi
mkdir -p "$PROJECT_ROOT/build/ios/ipa"
cp "$BUILD_DIR/Runner.ipa" "$PROJECT_ROOT/build/ios/ipa/app.ipa"

echo ">>> [6/6] Upload to App Store Connect..."
# Note: xcrun altool was deprecated Nov 2023, using iTMSTransporter instead
xcrun iTMSTransporter -m upload \
    -f "$BUILD_DIR/Runner.ipa" \
    -apiKey "$API_KEY" \
    -apiIssuer "$API_ISSUER"

echo "✓ iOS upload complete!"
