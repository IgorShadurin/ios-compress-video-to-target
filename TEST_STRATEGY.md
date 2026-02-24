# Compression Test Strategy

## Scope
- Validate compression planning logic first (unit tests in `CompressionPlannerTests`).
- Validate conversion behavior in app runtime (simulator/manual) using synthetic videos in `/Users/test/XCodeProjects/CompressTarget_data`.

## Edge Cases (Unit)
- Unit conversion correctness for KB/MB/GB.
- Invalid target size input (non-positive values).
- Enforce max compression ratio of 30x from source size.
- Target format resolution:
  - `Auto` keeps source format when supported.
  - `Auto` falls back to supported format when source format not available.
  - Explicit unsupported format should fail.
- Planner quality constraints:
  - Estimated output must stay at or below target bytes.
  - Video bitrate must not exceed source bitrate.
- Retry plan behavior:
  - Retry output estimate remains at/below target.
  - Retry lowers bitrate and does not increase resize scale.
- HDR toggle behavior:
  - `Remove HDR` forces non-HDR-friendly codec/output assumptions.

## Combination Sweep (Unit)
- Generate full synthetic metadata matrix over combinations:
  - Durations: 5, 30, 60, 120 seconds.
  - Resolutions: 720p, 1080p, 2160p.
  - HDR: on/off.
  - Containers: MOV, MP4, M4V, 3GP, 3G2.
  - Codecs: H.264, HEVC.
- Assert planner always returns valid output format, legal scale, and estimated size <= target.
- Assert explicit format selection works for dynamic identifiers (library-supported identifiers beyond hardcoded known list).

## Runtime/Integration Checks (Manual)
- Pick each generated video from `/Users/test/XCodeProjects/CompressTarget_data`.
- Verify source metadata display (duration, dimensions, codec, HDR/SDR, size).
- Validate UI input checks:
  - Reject invalid size.
  - Reject targets below 30x limit.
- Convert with/without resize and with/without HDR removal.
- Confirm second pass starts automatically when first pass exceeds target.
- Confirm oversized first-pass file is removed.
- Confirm final output is <= target and size is shown in human-readable format.
- Confirm save-to-gallery works.
- Confirm settings persist across app relaunch.
