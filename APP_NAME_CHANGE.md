# iOS App Rename Playbook (LLM Instructions)

Use this as a strict checklist to rename an iOS app and Xcode project.  
Do not skip steps. Use placeholders:
- `<APP_NAME>`: new app/project/target name
- `<BUNDLE_ID>`: new bundle identifier
- `<APP_DIR>`: app source folder (contains `*.swift`, `Assets.xcassets`, `*.lproj`)
- `<PROJECT_FILE>`: `<APP_NAME>.xcodeproj`
- `<WORKSPACE_FILE>`: `<APP_NAME>.xcworkspace`

## App Rename (User Will See)
- Update display name in `Config/AppInfo.plist` (`CFBundleDisplayName` and app title fields).
- Update localized app title and user-facing brand strings in:
  - `<APP_DIR>/en.lproj/Localizable.strings`
  - `<APP_DIR>/es.lproj/Localizable.strings`
  - `<APP_DIR>/ru.lproj/Localizable.strings`
- Update any visible website/help/privacy links and brand copy in Swift UI files under `<APP_DIR>/` (for example `ContentView.swift`).
- Confirm no stale brand strings remain:
  - run `rg -n "<OLD_NAME>|<old_name_lowercase>" <APP_DIR> Config README.md`

## Project Rename (Developer Only)
- Rename file system paths:
  - app source folder: `<APP_DIR>/` (folder name must match project references)
  - project: `<PROJECT_FILE>`
  - workspace: `<WORKSPACE_FILE>`
  - app entry file: `<APP_DIR>/<APP_NAME>App.swift`
  - entitlements file: `<APP_DIR>/<APP_NAME>.entitlements`
- Update Xcode project internals in `<PROJECT_FILE>/project.pbxproj`:
  - target name
  - product name / app binary name
  - scheme references
  - build settings paths (`CODE_SIGN_ENTITLEMENTS`, source folder paths)
  - Pods integration references (`Pods-<APP_NAME>`, `Pods_<APP_NAME>.framework`)
- Update bundle identifier in build settings and plist references to `<BUNDLE_ID>`.
- Reset build number for a newly renamed app:
  - In `<PROJECT_FILE>/project.pbxproj`, set `CURRENT_PROJECT_VERSION = 1;` for app target build configurations (Debug and Release).
  - In `Config/AppInfo.plist`, ensure `CFBundleVersion` is sourced from build settings:
    - `<key>CFBundleVersion</key>`
    - `<string>$(CURRENT_PROJECT_VERSION)</string>`
  - In Xcode UI (equivalent): select app target -> `Build Settings` -> `Versioning` -> `Current Project Version` = `1`.
- Update `Podfile` target block name to `<APP_NAME>`, then run `pod install`.
- Update workspace project link in `<WORKSPACE_FILE>/contents.xcworkspacedata`.
- Update docs and scripts that call xcodebuild:
  - workspace argument
  - scheme argument
  - app path under DerivedData
  - simulator launch bundle ID
- Validate:
  - run `xcodebuild -workspace <WORKSPACE_FILE> -scheme <APP_NAME> -destination 'platform=iOS Simulator,name=iPhone 17' build`
  - ensure output ends with `** BUILD SUCCEEDED **`
- Final verification:
  - run `rg -n "<OLD_NAME>|<old_name_lowercase>|<OLD_BUNDLE_ID>" . --hidden --glob '!.git/**'`
  - expected result: no matches outside historical notes.
