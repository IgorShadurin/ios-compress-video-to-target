# AwesomeApp iOS Client

This directory contains the native iOS companion for the AwesomeApp platform. The app targets iOS 16+ and focuses on account linking (Google/Apple), subscription management, and launching web-based creators from a mobile-friendly shell. It talks exclusively to the Next.js backend that lives in `web/app.awesomeapp.com` via the mobile API surface (`/api/mobile/**`).

## Requirements

- macOS with Xcode 16 (build logs currently reference 17A400) and the iOS 17 simulators installed.
- CocoaPods (for Google Sign-In frameworks) – install via `gem install cocoapods` if needed.
- Node/Next backend running the latest AwesomeApp server so mobile endpoints exist and the OAuth credentials match this app’s bundle identifiers.

## Repository Layout

```
Config/
  AppInfo.plist         # Environment-specific values (API base URL, Google client ID, etc.)
Pods/                  # Managed by CocoaPods (ignored in git)
Podfile                # Declares GoogleSignIn dependencies
AwesomeApp/           # App source root
  App/                # App entry + top-level UI composition
  Core/               # Cross-cutting infrastructure (networking, persistence, config, extensions)
  ViewModels/         # Screen state + app orchestration
  Features/           # Feature modules grouped by domain
    Auth/
    Characters/
    Duration/
    Languages/
    Projects/
    Templates/
    Voices/
  Assets.xcassets/    # Icons and visual assets
  *.lproj/            # Localized strings
AwesomeApp.xcworkspace     # Preferred workspace after running `pod install`
```

## Installation & First Run

```bash
cd /Users/test/XCodeProjects/AwesomeApp
pod install                       # installs GoogleSignIn + support pods
open AwesomeApp.xcworkspace            # always open the workspace, not the .xcodeproj
# Select the “AwesomeApp” scheme and the "iPhone 17" simulator, then build/run
```

To surface compiler errors exactly as CI does, or when you need a log for QA, run:

```bash
set -o pipefail && xcodebuild -workspace AwesomeApp.xcworkspace   -scheme AwesomeApp   -destination 'platform=iOS Simulator,name=iPhone 17' build  2>&1 | tee /tmp/xcodebuild.log
```

The build succeeds today with Signing Identity “Sign to Run Locally”. Change the team/profile only when preparing Ad Hoc/TestFlight builds.

## Runtime Configuration

All runtime knobs are Info.plist keys stored in `Config/AppInfo.plist`. During the build the file is merged into the app target, so edits here affect every environment:

| Key | Description |
| --- | --- |
| `MOBILE_API_BASE_URL` | Base URL for the Next.js mobile API (default `https://app.awesomeapp.com`). Must point at the deployment that exposes `/api/mobile/auth/*` and `/api/mobile/projects`. |
| `STORAGE_BASE_URL` | Public root of the storage deployment used for downloading media (default `https://static.awesomeapp.com/`). |
| `STORAGE_UPLOAD_ORIGIN` | Origin that storage expects for signed uploads. This should mirror `NEXT_PUBLIC_STORAGE_BASE_URL` on web so the RSA-signed payloads are accepted. |
| `GOOGLE_IOS_CLIENT_ID` | OAuth client created in Google Cloud Console for bundle id `org.video.ai.AwesomeApp`. The same value must be present in the backend `.env` (`GOOGLE_IOS_CLIENT_ID=…`) or the server will reject mobile logins with “payload audience != requiredAudience”. |

> `AwesomeApp/Core/Configuration/AppConfiguration.swift` documents the defaults that ship in code.

### Google Sign-In Checklist

1. In [Google Cloud Console](https://console.cloud.google.com/apis/credentials) create an **iOS OAuth Client** with bundle ID `org.video.ai.AwesomeApp`.
2. Copy the client ID into `GOOGLE_IOS_CLIENT_ID` and into the backend `.env`.
3. Ensure `CFBundleURLTypes[0].CFBundleURLSchemes[0]` is the reverse client ID (already committed as `com.googleusercontent.apps.…`).
4. Rebuild; you should no longer see “Wrong recipient, payload audience != requiredAudience”.

### Sign in with Apple

- Capability **Sign In with Apple** is already added via `AwesomeApp.entitlements`. Confirm the bundle ID is enabled for this capability in Apple Developer Console.
- The same bundle ID (`org.video.ai.AwesomeApp`) must appear in the web backend as `APPLE_IOS_CLIENT_ID` so `/api/mobile/auth/apple` can verify tokens.
- When adding a new environment, update the Service ID + web domain as described in `web/app.awesomeapp.com/APPLE_AUTH_RU.md`, but keep the iOS bundle unchanged to avoid regenerating private keys.

## Authentication & Backend Expectations

- The app never stores passwords. It retrieves Google/Apple identity tokens and POSTs them to `/api/mobile/auth/{google|apple}` along with device metadata.
- The server links providers by email. If Google or Apple returns an unverified email, the backend will reject the link; surface that to the user via the alert strings in `localizable.strings`.
- The mobile session manager on the backend issues refresh tokens per device. Logging out from Settings revokes the server-side session and clears the keychain so a fresh login is required next time.
- Server logs now emit `[next-auth][error] …` entries that mirror what the client sees. Use them when debugging unexplained `AccessDenied` or `OAuthAccountNotLinked` errors.

## Localization & UI Assets

- Strings: `AwesomeApp/en.lproj`, `ru.lproj`, `es.lproj`. Add new languages by duplicating these files and updating `LanguageManager`.
- Icons: Google uses `Assets.xcassets/GoogleIcon.imageset/GoogleIcon.pdf` (vector exported from the official SVG); Apple uses the SF Symbol `applelogo`. Keep additions vector-based for sharp rendering on all scales.

## Troubleshooting

| Symptom | Resolution |
| --- | --- |
| `Wrong recipient, payload audience != requiredAudience` (Google login) | Backend missing `GOOGLE_IOS_CLIENT_ID` or the value doesn’t match `Config/AppInfo.plist`. Update both places and restart the web server. |
| Apple login works only once | Check that the Apple key (.p8) and Key ID configured in the backend match the Service ID and haven’t expired. |
| `Cannot find 'GoogleIcon' in asset catalog` at runtime | Ensure `GoogleIcon.imageset` lives under `AwesomeApp/Assets.xcassets` and is part of the target membership, then clean build folder. |
| Build fails with `pod` errors | Run `pod repo update && pod install`. Only commit `Podfile` and `Podfile.lock`. |

## Release Checklist

1. Update Marketing Version / Build in Xcode.
2. `pod install` to sync dependencies (and commit the lockfile). 
3. Run the validation build command above; inspect `/tmp/xcodebuild.log` for warnings.
4. Manually verify Google + Apple login/linking from the simulator pointed at production (`MOBILE_API_BASE_URL=https://app.awesomeapp.com`).
5. Coordinate with the web team to ensure the backend `.env` values (`GOOGLE_IOS_CLIENT_ID`, `APPLE_IOS_CLIENT_ID`, storage URLs) match what ships in `Config/AppInfo.plist`.

That’s everything you need to configure, build, and troubleshoot the AwesomeApp iOS app without digging through the web repository.
