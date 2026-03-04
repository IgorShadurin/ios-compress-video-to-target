# Build and Launch Commands (Dedicated iOS Simulator)

This project uses a dedicated simulator binding file (outside git):

`/Users/test/XCodeProjects/CompressTarget_data/CompressTarget.simulator.env`

## 1) Load dedicated simulator info

```sh
SIM_ENV=/Users/test/XCodeProjects/CompressTarget_data/CompressTarget.simulator.env
source "$SIM_ENV"
echo "$SIM_DEVICE_NAME $SIM_DEVICE_UDID $SIM_RUNTIME"
```

## 2) Boot dedicated simulator (if needed)

```sh
SIM_ENV=/Users/test/XCodeProjects/CompressTarget_data/CompressTarget.simulator.env
source "$SIM_ENV"
xcrun simctl boot "$SIM_DEVICE_UDID" || true
open -a Simulator
```

## 3) Build for the dedicated simulator

```sh
SIM_ENV=/Users/test/XCodeProjects/CompressTarget_data/CompressTarget.simulator.env
source "$SIM_ENV"
xcodebuild -project CompressVideoToTargetSize.xcodeproj -scheme CompressVideoToTargetSize -destination "id=$SIM_DEVICE_UDID" build
```

## 4) Install and launch on dedicated simulator

```sh
SIM_ENV=/Users/test/XCodeProjects/CompressTarget_data/CompressTarget.simulator.env
source "$SIM_ENV"
APP_PATH=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug-iphonesimulator/CompressVideoToTargetSize.app' -print0 | xargs -0 ls -td | head -n 1)

xcrun simctl install "$SIM_DEVICE_UDID" "$APP_PATH"
xcrun simctl launch "$SIM_DEVICE_UDID" org.icorpvideo.CompressVideoToTargetSize
```

## 5) One-shot command (build + install + launch)

```sh
set -euo pipefail
SIM_ENV=/Users/test/XCodeProjects/CompressTarget_data/CompressTarget.simulator.env
source "$SIM_ENV"
xcrun simctl boot "$SIM_DEVICE_UDID" >/dev/null 2>&1 || true
xcodebuild -project CompressVideoToTargetSize.xcodeproj -scheme CompressVideoToTargetSize -destination "id=$SIM_DEVICE_UDID" build
APP_PATH=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Build/Products/Debug-iphonesimulator/CompressVideoToTargetSize.app' -print0 | xargs -0 ls -td | head -n 1)
xcrun simctl install "$SIM_DEVICE_UDID" "$APP_PATH"
xcrun simctl launch "$SIM_DEVICE_UDID" org.icorpvideo.CompressVideoToTargetSize
```

## 6) Capture build log

```sh
SIM_ENV=/Users/test/XCodeProjects/CompressTarget_data/CompressTarget.simulator.env
source "$SIM_ENV"
set -o pipefail && xcodebuild -project CompressVideoToTargetSize.xcodeproj -scheme CompressVideoToTargetSize -destination "id=$SIM_DEVICE_UDID" build 2>&1 | tee /tmp/xcodebuild.log
```

## 7) Create and boot a fresh iPhone 17 simulator

```sh
SIM_NAME="CompressTarget-Showcase-iPhone17-$(date +%Y%m%d-%H%M%S)"
RUNTIME_ID="com.apple.CoreSimulator.SimRuntime.iOS-26-2"
DEVICE_TYPE_ID="com.apple.CoreSimulator.SimDeviceType.iPhone-17"
UDID=$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE_ID" "$RUNTIME_ID")
echo "UDID=$UDID"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
open -a Simulator --args -CurrentDeviceUDID "$UDID"
```

## 8) Build + install app to a selected simulator UDID

```sh
UDID="<PASTE_UDID_HERE>"
DERIVED="/tmp/CompressTargetShowcaseDD"
rm -rf "$DERIVED"
xcodebuild -project CompressVideoToTargetSize.xcodeproj -scheme CompressVideoToTargetSize -configuration Debug -destination "id=$UDID" -derivedDataPath "$DERIVED" build
xcrun simctl uninstall "$UDID" org.icorpvideo.CompressVideoToTargetSize >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/CompressVideoToTargetSize.app"
```

## 9) Exact light/dark showcase capture commands (all 14 screens)

```sh
set -euo pipefail
PROJECT_ROOT="/Users/test/XCodeProjects/CompressTarget"
UDID="<PASTE_UDID_HERE>"
BUNDLE_ID="org.icorpvideo.CompressVideoToTargetSize"
FRAME_SCRIPT="/Users/test/XCodeProjects/APPLE_HELPERS/iphone17-frame.sh"
RAW_DIR="/tmp/shot_work"

mkdir -p "$PROJECT_ROOT/showcase/high" "$PROJECT_ROOT/showcase/preview" "$RAW_DIR"

capture_one() {
  mode="$1"
  step="$2"
  name="$3"
  variant="${4:-}"
  wait_s="${5:-2.0}"
  raw="$RAW_DIR/${name}_raw.png"

  xcrun simctl ui "$UDID" appearance "$mode"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

  if [ -n "$variant" ]; then
    xcrun simctl launch "$UDID" "$BUNDLE_ID" -uiShowcaseStep "$step" -uiShowcaseVariant "$variant" >/dev/null
  else
    xcrun simctl launch "$UDID" "$BUNDLE_ID" -uiShowcaseStep "$step" >/dev/null
  fi

  sleep "$wait_s"
  xcrun simctl io "$UDID" screenshot "$raw" >/dev/null
  sips -g pixelWidth -g pixelHeight "$raw"

  "$FRAME_SCRIPT" "$raw" "$PROJECT_ROOT/showcase/high/${name}.png"
  magick "$PROJECT_ROOT/showcase/high/${name}.png" -filter Lanczos -resize 220x -strip "$PROJECT_ROOT/showcase/preview/${name}.png"
}

# Light (existing base names)
capture_one light source main-page "" 2.0
capture_one light settings ready-to-convert "" 2.2
capture_one light done done-window "" 2.8
capture_one light paywall paywall-window "" 2.2
capture_one light settings advanced-options-bottom advanced-bottom 2.4
capture_one light settings format-dropdown-open format-dropdown 2.4
capture_one light settings resolution-dropdown-open resolution-dropdown 2.4

# Dark (suffix -dark)
capture_one dark source main-page-dark "" 2.0
capture_one dark settings ready-to-convert-dark "" 2.2
capture_one dark done done-window-dark "" 2.8
capture_one dark paywall paywall-window-dark "" 2.2
capture_one dark settings advanced-options-bottom-dark advanced-bottom 2.4
capture_one dark settings format-dropdown-open-dark format-dropdown 2.4
capture_one dark settings resolution-dropdown-open-dark resolution-dropdown 2.4
```

## 10) Quick validation for the 14 screenshot files

```sh
PROJECT_ROOT="/Users/test/XCodeProjects/CompressTarget"
ls -1 "$PROJECT_ROOT/showcase/high" | rg "^(main-page|ready-to-convert|done-window|paywall-window|advanced-options-bottom|format-dropdown-open|resolution-dropdown-open)(-dark)?\\.png$" | wc -l
ls -1 "$PROJECT_ROOT/showcase/preview" | rg "^(main-page|ready-to-convert|done-window|paywall-window|advanced-options-bottom|format-dropdown-open|resolution-dropdown-open)(-dark)?\\.png$" | wc -l
```
