#!/bin/bash
# =============================================================================
# Dual-Platform Release (iOS + Android, fvm-aware)
#
# Required env vars (iOS):
#   TEAM_ID, CERT_HASH, PROVISIONING_PROFILE, API_KEY, API_ISSUER
# Required (Android):
#   android/key.properties + android/fastlane/ setup
# Optional:
#   DART_DEFINES   - space-separated KEY=VALUE for --dart-define
#   ANDROID_TRACK  - Play Store track (default: production)
#
# Usage: ./fvm_release_all.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ANDROID_TRACK="${ANDROID_TRACK:-production}"
FAILED=0

echo "========================================"
echo "  Dual-Platform Release (fvm)"
echo "========================================"
echo ""

# iOS
echo ">>> [1/2] iOS App Store..."
if "$SCRIPT_DIR/fvm_ios_upload.sh"; then
    echo "✓ iOS done"
else
    echo "✗ iOS failed"
    FAILED=1
fi
echo ""

# Android
echo ">>> [2/2] Android Google Play ($ANDROID_TRACK)..."
if "$SCRIPT_DIR/fvm_android_upload.sh" "$ANDROID_TRACK"; then
    echo "✓ Android done"
else
    echo "✗ Android failed"
    FAILED=1
fi
echo ""

echo "========================================"
if [ "$FAILED" -eq 0 ]; then
    echo "  ✓ Both platforms uploaded!"
else
    echo "  ⚠ Some uploads failed. Check above."
fi
echo "========================================"

exit $FAILED
