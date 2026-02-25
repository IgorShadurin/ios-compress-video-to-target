#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="${PROJECT:-CompressVideoToTargetSize.xcodeproj}"
SCHEME="${SCHEME:-CompressVideoToTargetSize}"

DEVICE_UDID="${1:-}"
OUTPUT_DIR="${2:-/tmp/CompressTargetLogs}"

if [[ -z "$DEVICE_UDID" ]]; then
  DEVICE_UDID="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showdestinations 2>/dev/null | sed -nE 's/.*platform:iOS, arch:arm64, id:([0-9A-F-]+),.*/\1/p' | head -n 1)"
fi

if [[ -z "${DEVICE_UDID:-}" ]]; then
  echo "No connected iPhone detected."
  exit 1
fi

BUNDLE_ID="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null | awk -F' = ' '/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=/{print $2; exit}')"
if [[ -z "${BUNDLE_ID:-}" ]]; then
  echo "Failed to resolve bundle id."
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
STAMP="$(date +%Y%m%d_%H%M%S)"
TARGET_FILE="$OUTPUT_DIR/conversion-diagnostics_${STAMP}.jsonl"

echo "Device: $DEVICE_UDID"
echo "Bundle: $BUNDLE_ID"
echo "Listing available diagnostics files..."
xcrun devicectl device info files \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --subdirectory Documents/Diagnostics \
  --recurse

echo "Pulling logs to: $TARGET_FILE"
xcrun devicectl device copy from \
  --device "$DEVICE_UDID" \
  --domain-type appDataContainer \
  --domain-identifier "$BUNDLE_ID" \
  --source Documents/Diagnostics/conversion-diagnostics.jsonl \
  --destination "$TARGET_FILE"

echo "Done."
