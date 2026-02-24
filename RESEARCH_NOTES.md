# Public Research Notes

## Goal
Identify Apple-supported APIs and patterns for:
- Reading source video metadata
- Transcoding with bitrate/format control
- Handling HDR/SDR output behavior
- Saving resulting videos to Photos library
- User video picking flow

## Sources
- AVFoundation media read/write overview: https://developer.apple.com/documentation/avfoundation/media-reading-and-writing
- AVAssetExportSession API (supported file types/export presets): https://developer.apple.com/documentation/avfoundation/avassetexportsession
- AVAssetWriter API (custom output settings/bitrates): https://developer.apple.com/documentation/avfoundation/avassetwriter
- PhotosPicker API for selecting videos from library: https://developer.apple.com/documentation/photosui/photospicker
- Photo library save API for videos: https://developer.apple.com/documentation/photos/phassetchangerequest/creationrequestforassetfromvideo(atfileurl:)

## Applied Decisions
- Use `PhotosPicker` to choose gallery videos.
- Use `AVAsset` track inspection to read source metadata (duration, dimensions, bitrate estimate, media characteristics).
- Use `AVAssetReader` + `AVAssetWriter` for controlled transcode parameters (container + target bitrate).
- Implement planner-first flow to compute highest quality under target-size budget and cap compression ratio at 30x.
- Implement retry transcode pass when first output exceeds target bytes.
- Save final output with `PHAssetChangeRequest.creationRequestForAssetFromVideo`.
