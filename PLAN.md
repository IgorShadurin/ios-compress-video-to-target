# CompressTarget Implementation Plan

- [x] Confirm baseline project builds and capture current constraints (targets, tests, iOS version, launch command).
- [x] Create test strategy with edge cases first (size validation, units conversion, max compression, resize toggle, HDR removal toggle, format resolution, multi-pass retry).
- [x] Add/prepare test target and failing unit tests for compression planning/calculation logic.
- [x] Rename app to **Compress Video to Target Size** and set minimum iOS to 18.
- [x] Replace existing app flow with a video-compression-focused UI (picker, target size input + units dropdown, resize toggle, HDR removal toggle, output format dropdown with Auto).
- [x] Implement settings persistence and restore on next app start.
- [x] Implement source metadata inspection (duration, dimensions, estimated size, codec/HDR detection when available).
- [x] Implement target planning function that chooses highest possible quality under target-size constraint.
- [x] Implement conversion pipeline with at least one retry pass when output exceeds target; show explicit retry status in UI and clean up oversized interim file.
- [x] Implement save-to-gallery option after conversion and show human-readable file sizes.
- [x] Generate/collect external test videos into `/Users/test/XCodeProjects/CompressTarget_data` covering diverse formats/resolutions/HDR/durations (5s to 120s).
- [x] Add automated tests over generated source combinations for target-format selection and size-planning logic.
- [x] Remove unused legacy code/files from template app and keep only required functionality.
- [x] Build and run on iOS simulator using project launch instructions after all changes are complete.
- [x] Mark all tasks complete and summarize outcomes/limitations.

## Format Coverage Follow-up Plan

- [x] Audit app code for hardcoded output/source format limitations against AVFoundation-supported file type APIs.
- [x] Refactor output-format discovery to dynamically enumerate compatible AVFoundation types for each picked source.
- [x] Ensure planner and settings support arbitrary container identifiers (not just MOV/MP4/M4V).
- [x] Expand unit tests to cover additional known containers (3GP/3G2) plus unknown dynamic identifiers.
- [x] Rebuild, retest, and relaunch on simulator to validate end-to-end stability after format-support changes.

## UI Clarity Follow-up Plan

- [x] Review Apple guidance for simple task-focused app flows and loading feedback.
- [x] Update UI to progressive disclosure: hide Convert and Result until they become relevant.
- [x] Add a blocking conversion progress modal with explicit warning to keep the app open.
- [x] Rebuild, retest, and relaunch on simulator.

## Crash Fix Follow-up Plan

- [x] Analyze simulator crash report and identify failing code path (`VideoMetadataInspector.canWrite`).
- [x] Remove unsafe dynamic output file-type probing that can trigger `AVAssetWriter` Objective-C exceptions.
- [x] Restrict output probing to writer-safe video containers and keep source compatibility checks via export sessions.
- [x] Rebuild and run automated smoke pass across `/Users/test/XCodeProjects/CompressTarget_data`.
- [x] Rebuild and relaunch on simulator.

## Resolution Control Follow-up Plan

- [x] Rename misleading resize label to clearer wording and remove `10x` copy from UI.
- [x] Add optional output resolution picker tied to selected source, always including same-as-source.
- [x] Persist selected resolution preference and apply it in planner/retry logic.
- [x] Add planner tests to confirm preferred resolution cap is respected.
- [x] Rebuild, retest, and relaunch on simulator.

## Target Size Slider Follow-up Plan

- [x] Add a full-width target-size slider under the size and unit inputs.
- [x] Keep manual target-size entry available so users can enter any value directly.
- [x] Show quick min/max hints for the slider in the selected unit.
- [x] Rebuild, retest, and relaunch on simulator.

## Source Preview Responsiveness Follow-up Plan

- [x] Show an inline, compact preview immediately after video selection.
- [x] Load metadata and supported formats progressively so UI stays responsive.
- [x] Show a loading indicator while source details are still being prepared.
- [x] Rebuild, retest, and relaunch on simulator.

## Slider Integer Follow-up Plan

- [x] Make target size slider update value as integers only while dragging.
- [x] Keep manual text input available for direct custom entry.
- [x] Rebuild, retest, and relaunch on simulator.

## Fast Source Loading Follow-up Plan

- [x] Research Apple AVFoundation guidance for faster preview and metadata loading.
- [x] Replace live preview player with first-frame thumbnail preview for faster initial render.
- [x] Load lightweight source info immediately, then load deeper metadata and format compatibility in later phases.
- [x] Reduce format discovery overhead by using compatible presets directly and early-exit once writer-safe formats are found.
- [x] Rebuild, retest, and relaunch on simulator.

## Picker Latency Follow-up Plan

- [x] Research the fastest iOS media-picking path to avoid expensive early file transfers.
- [x] Switch to `PhotosPicker` current-item encoding to avoid unnecessary transcoding.
- [x] Add PhotoKit-first loading path: fetch PHAsset thumbnail/quick info immediately, resolve playable URL in background, use Transferable only as fallback.
- [x] Rebuild, retest, and relaunch on simulator.

## Three-Step Flow Follow-up Plan

- [x] Redesign UI into three explicit steps: Source, Settings, Convert.
- [x] Immediately transition to Step 2 after source pick and show loading state while metadata is prepared.
- [x] Re-layout Step 2 to keep compact source preview, source info, and target settings together with the convert button directly below settings.
- [x] Rebuild, launch on simulator, and verify step transitions and conversion screen behavior.

## Header Space Optimization Follow-up Plan

- [x] Reduce navigation/header copy and simplify top progress indicator to reclaim vertical space.
- [x] Shorten Step 1 hero text and reduce hero card height.
- [x] Rebuild and relaunch on simulator.

## Photo Permission Prompt Follow-up Plan

- [x] Identify why photo-library access expansion prompt appears after selecting a video.
- [x] Disable PhotoKit fast-path for non-full-access states so picker selection does not trigger extra read prompt.
- [x] Rebuild and relaunch on simulator.

## Conversion Crash Follow-up Plan

- [x] Analyze crash stack for conversion failure at `AVAssetWriterInput.appendSampleBuffer`.
- [x] Make audio pipeline writer-safe by decoding reader audio to PCM before AAC re-encode.
- [x] Add append-loop guards for writer state, invalid sample data, and non-monotonic timestamps.
- [x] Run smoke conversions on diverse local dataset files (H.264/HEVC/HDR/ProRes, MP4/MOV, 720p-4K, 5s-120s).
- [x] Rebuild and relaunch on simulator.

## Display Name + Prompt Follow-up Plan

- [x] Fix app icon display name to a spaced, human-readable label.
- [x] Upgrade `prompt.txt` to require both automated tests and manual simulator click-through verification.
- [x] Rebuild, reinstall, and relaunch on simulator.

## Conversion Progress Bar Follow-up Plan

- [x] Expose real conversion progress from the media pipeline while samples are processed.
- [x] Wire progress updates into the conversion view model for first and retry passes.
- [x] Show a determinate progress bar with percentage in Step 3 when progress is available.
- [x] Rebuild and relaunch on simulator.

## Conversion Cancel Follow-up Plan

- [x] Add service-level cancellation to stop active AV reader/writer operations.
- [x] Add a ViewModel cancel action and cancellation state handling.
- [x] Add a `Cancel conversion` control in Step 3 while conversion is running.
- [x] Rebuild and relaunch on simulator.

## Prompt Cancelability Follow-up Plan

- [x] Update `prompt.txt` to require cancel controls for all heavy actions.
- [x] Update `prompt.txt` testing requirements to include manual cancel-flow validation.

## Button Icons + Label Cleanup Follow-up Plan

- [x] Add relevant icons to all visible action buttons in the main flow.
- [x] Add icon to `Cancel conversion` button.
- [x] Remove conversion status text label from Step 3 card.
- [x] Remove estimation reason label from Step 3 estimation card.
- [x] Update `prompt.txt` to require relevant icons for all buttons.
- [x] Rebuild and relaunch on simulator.

## Prompt Fresh Style Follow-up Plan

- [x] Update `prompt.txt` to require a distinctly new UI style for each new app.
- [x] Ensure the prompt preserves an appealing quality bar (hierarchy, spacing, contrast, cohesion).

## Prompt Compact Screens Follow-up Plan

- [x] Update `prompt.txt` to require compact screens that fit core content/actions on any iPhone size.
- [x] Add explicit small-iPhone-first guidance to reduce unnecessary scrolling.

## Prompt Light/Dark Follow-up Plan

- [x] Update `prompt.txt` to require correct Light/Dark mode support with adaptive colors.
- [x] Add explicit verification requirement for key screens/states in both modes.

## App Light/Dark Support Follow-up Plan

- [x] Replace non-adaptive surface styling with semantic system backgrounds and contrast-aware borders.
- [x] Ensure status/error/success accents use semantic adaptive colors.
- [x] Make the hero surface color palette mode-aware for readability and visual consistency.
- [x] Build and verify launch in simulator.
- [x] Verify key screen rendering in both Light and Dark appearance modes.

## Localization + Markets Follow-up Plan

- [x] Research Apple App Store supported localization languages from official documentation.
- [x] Define top-country localization set constrained to Latin-script locales plus Russian/Ukrainian exception.
- [x] Add localization resources for selected locales and wire runtime strings to localization keys.
- [x] Configure app bundle localizations for selected locales.
- [x] Build and run on simulator.
- [x] Verify localization resources are packaged in app bundle.

## Step Header Sizing Follow-up Plan

- [x] Increase step indicator markers in top progress header by 2x.
- [x] Keep marker numerals readable at the new size.
- [x] Build and run on simulator to validate layout on iPhone.

## Files Import Follow-up Plan

- [x] Add a source import button for Files on Step 1 UI.
- [x] Implement safe file-import handling in ViewModel and feed imported URLs into the existing metadata/conversion flow.
- [x] Update localized copy for source import instructions and new Files button text.
- [x] Update `prompt.txt` to require Gallery + Files import for file-based apps.
- [x] Build and run on simulator to verify both app launch and Files import entry point visibility.

## Square Preview Follow-up Plan

- [x] Change source preview thumbnail container to a square aspect ratio.
- [x] Keep crop behavior stable (`scaledToFill`) to avoid layout issues from extreme video ratios.
- [x] Build and run on simulator to verify Step 2 preview layout.

## Prompt Screen-Fit QA Follow-up Plan

- [x] Add prompt requirement for final simulator screenshot checks across all screens/states.
- [x] Specify required device-size classes: small (mini), standard, and large (Pro/Pro Max).
- [x] Require explicit `PASS`/`FAIL` reporting for screen-fit validation with issue details on failure.

## Clickable Step Indicators Follow-up Plan

- [x] Make step indicators clickable for backward navigation.
- [x] Show confirmation before navigating back from the current step.
- [x] Reset selected source video when confirming navigation to Step 1.
- [x] Build and run on simulator to validate behavior and layout.

## Monetization + Daily Limit Follow-up Plan

- [x] Add purchase domain layer for weekly/monthly/lifetime plans and entitlement checks.
- [x] Add local daily free-limit store to enforce 1 free conversion per day.
- [x] Integrate purchase + quota state into `VideoCompressionViewModel` and conversion gating.
- [x] Add paywall UI and upgrade/restore actions in app screens.
- [x] Add user-facing quota/premium status messaging.
- [x] Build and run on simulator to validate compile + launch.

## README Showcase Screenshots Follow-up Plan

- [x] Add deterministic screenshot-launch states for Step 1, Step 2, and Step 3.
- [x] Capture simulator screenshots for all three steps and store them in a project directory.
- [x] Update `README.md` with a showcase section embedding the three screenshots.
- [x] Build and run once to verify screenshot mode and app launch stability.
