#!/bin/bash
# =============================================================================
# Android Google Play Upload (fvm-aware)
#
# Required:
#   - android/key.properties with signing config
#   - android/fastlane/ with service account JSON
# Optional:
#   DART_DEFINES  - space-separated KEY=VALUE pairs for --dart-define
#   PROJECT_ROOT  - project directory (default: pwd)
#
# Usage: ./fvm_android_upload.sh [track]
#   track: internal | alpha | beta | production (default: production)
# =============================================================================

set -euo pipefail

TRACK="${1:-production}"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"

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

echo ">>> [1/2] Flutter build appbundle..."
$FLUTTER build appbundle --release $DEFINE_FLAGS

AAB_PATH="$PROJECT_ROOT/build/app/outputs/bundle/release/app-release.aab"
[ -f "$AAB_PATH" ] || { echo "ERROR: AAB not found: $AAB_PATH"; exit 1; }

AAB_SIZE=$(du -h "$AAB_PATH" | cut -f1)
echo "✓ AAB built ($AAB_SIZE)"

echo ">>> [2/2] Upload to Google Play ($TRACK)..."
cd "$PROJECT_ROOT/android"

if [ -f "fastlane/Fastfile" ]; then
    bundle exec fastlane supply \
        --aab "$AAB_PATH" \
        --track "$TRACK" \
        --skip_upload_metadata \
        --skip_upload_images \
        --skip_upload_screenshots
else
    echo "ERROR: No fastlane config found."
    echo "Manual upload: $AAB_PATH"
    echo "Setup: cd android && fastlane init"
    exit 1
fi

echo ""
echo "✓ Android upload complete! ($TRACK)"
echo "AAB: $AAB_PATH"
