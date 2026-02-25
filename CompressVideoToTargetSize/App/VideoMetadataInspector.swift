import AVFoundation
import Foundation
import Photos
import UIKit
import UniformTypeIdentifiers

struct VideoMetadataInspector {
    private let writerSupportedContainers: [CompressionContainer] = [.mp4, .mov, .m4v]
    private let imageManager = PHImageManager.default()

    func allWriterOutputFormats() -> [CompressionContainer] {
        writerSupportedContainers.isEmpty ? [.mov] : writerSupportedContainers
    }

    func fetchAsset(localIdentifier: String) -> PHAsset? {
        let results = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        return results.firstObject
    }

    func generatePreviewImage(from asset: PHAsset, maxDimension: CGFloat) async -> UIImage? {
        let targetSize = CGSize(width: maxDimension, height: maxDimension)
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            var resolved = false
            imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { image, info in
                guard !resolved else { return }
                if let isCancelled = info?[PHImageCancelledKey] as? Bool, isCancelled {
                    resolved = true
                    continuation.resume(returning: nil)
                    return
                }
                if info?[PHImageErrorKey] != nil {
                    resolved = true
                    continuation.resume(returning: nil)
                    return
                }

                if let image {
                    resolved = true
                    continuation.resume(returning: image)
                } else if let isInCloud = info?[PHImageResultIsInCloudKey] as? Bool, isInCloud {
                    resolved = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func requestPlayableURL(for asset: PHAsset) async -> URL? {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .fastFormat
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            imageManager.requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                let url = (avAsset as? AVURLAsset)?.url
                continuation.resume(returning: url)
            }
        }
    }

    func inspect(url: URL) async throws -> VideoMetadata {
        let asset = AVURLAsset(url: url)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw CompressionModelError.noVideoTrack
        }

        async let duration = asset.load(.duration)
        async let naturalSize = videoTrack.load(.naturalSize)
        async let preferredTransform = videoTrack.load(.preferredTransform)
        async let frameRateRaw = videoTrack.load(.nominalFrameRate)
        async let videoBitrateRaw = videoTrack.load(.estimatedDataRate)
        async let formatDescriptions = videoTrack.load(.formatDescriptions)
        async let mediaCharacteristics = videoTrack.load(.mediaCharacteristics)

        let naturalSizeValue = try await naturalSize
        let preferredTransformValue = try await preferredTransform
        let transformedRect = CGRect(origin: .zero, size: naturalSizeValue).applying(preferredTransformValue)
        let width = max(1, Int(abs(transformedRect.width).rounded()))
        let height = max(1, Int(abs(transformedRect.height).rounded()))

        let frameRateValue = try await frameRateRaw
        let frameRate = frameRateValue > 0 ? Double(frameRateValue) : 30

        let videoBitrateValue = try await videoBitrateRaw
        let sourceVideoBitrate = Int(max(400_000, videoBitrateValue))

        let formatDescriptionsValue = try await formatDescriptions
        let codec = VideoCodec.from(formatDescription: formatDescriptionsValue.first)
        let mediaCharacteristicsValue = try await mediaCharacteristics
        let hasHDR = mediaCharacteristicsValue.contains(.containsHDRVideo)

        let hasAudioTrack = !(try await asset.loadTracks(withMediaType: .audio)).isEmpty
        let sourceAudioBitrate = hasAudioTrack ? 128_000 : 0

        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .fileAllocatedSizeKey])
        let fileSize = Int64(resourceValues.fileSize ?? resourceValues.fileAllocatedSize ?? 0)
        let container = CompressionContainer(url: url)

        return VideoMetadata(
            sourceURL: url,
            durationSeconds: (try await duration).seconds,
            fileSizeBytes: fileSize,
            width: width,
            height: height,
            frameRate: frameRate,
            hasHDR: hasHDR,
            container: container,
            codec: codec,
            sourceVideoBitrate: sourceVideoBitrate,
            sourceAudioBitrate: sourceAudioBitrate,
            preferredTransform: preferredTransformValue
        )
    }

    func supportedOutputFormats(for url: URL, metadata _: VideoMetadata) async -> [CompressionContainer] {
        let asset = AVURLAsset(url: url)
        let allSupportedFileTypes = await discoverOutputFileTypes(for: asset)
        let writerSupportedSet = Set(writerSupportedContainers)

        let mapped = allSupportedFileTypes
            .filter(isVideoFileType)
            .map { CompressionContainer(fileType: $0) }

        let exportedWriterSupported = Array(Set(mapped)).filter { writerSupportedSet.contains($0) }
        let candidateContainers = exportedWriterSupported.isEmpty ? writerSupportedContainers : exportedWriterSupported
        let ordered = candidateContainers.sorted { lhs, rhs in
            let lhsIndex = writerSupportedContainers.firstIndex(of: lhs) ?? Int.max
            let rhsIndex = writerSupportedContainers.firstIndex(of: rhs) ?? Int.max
            if lhsIndex != rhsIndex {
                return lhsIndex < rhsIndex
            }
            return lhs.label < rhs.label
        }

        return ordered.isEmpty ? [.mov] : ordered
    }

    func generateFirstFramePreview(from url: URL, maxDimension: CGFloat) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        return await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            generator.generateCGImageAsynchronously(for: .zero) { image, _, _ in
                guard let image else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: UIImage(cgImage: image))
            }
        }
    }

    private func discoverOutputFileTypes(for asset: AVURLAsset) async -> Set<AVFileType> {
        var fileTypes = Set<AVFileType>()
        let candidatePresets: [String] = [
            AVAssetExportPresetPassthrough,
            AVAssetExportPresetHEVCHighestQuality,
            AVAssetExportPresetHighestQuality,
            AVAssetExportPresetMediumQuality
        ]
        let allWriterSupportedFileTypes = Set(writerSupportedContainers.map(\.avFileType))

        for preset in candidatePresets {
            let isCompatible = await AVAssetExportSession.compatibility(
                ofExportPreset: preset,
                with: asset,
                outputFileType: nil
            )
            guard isCompatible else {
                continue
            }

            guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
                continue
            }
            fileTypes.formUnion(exportSession.supportedFileTypes)
            if allWriterSupportedFileTypes.isSubset(of: fileTypes) {
                break
            }
        }

        return fileTypes
    }

    private func isVideoFileType(_ fileType: AVFileType) -> Bool {
        guard let type = UTType(fileType.rawValue) else {
            return false
        }

        if type.conforms(to: .audio) && !type.conforms(to: .movie) {
            return false
        }

        return type.conforms(to: .movie) || type.conforms(to: .audiovisualContent)
    }

}
