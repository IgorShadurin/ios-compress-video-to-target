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
