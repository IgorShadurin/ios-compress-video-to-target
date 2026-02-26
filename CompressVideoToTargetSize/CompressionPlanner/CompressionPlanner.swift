import Foundation

public enum CompressionUnit: String, CaseIterable, Codable {
    case kb
    case mb
    case gb

    public var multiplier: Double {
        switch self {
        case .kb: 1_000
        case .mb: 1_000_000
        case .gb: 1_000_000_000
        }
    }
}

public struct CompressionContainer: Hashable, Codable, Sendable {
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }

    public static let mov = CompressionContainer(identifier: "com.apple.quicktime-movie")
    public static let mp4 = CompressionContainer(identifier: "public.mpeg-4")
    public static let m4v = CompressionContainer(identifier: "com.apple.m4v-video")
    public static let gpp3 = CompressionContainer(identifier: "public.3gpp")
    public static let gpp23 = CompressionContainer(identifier: "public.3gpp2")

    public static let preferredAutoOrder: [CompressionContainer] = [.mp4, .mov, .m4v, .gpp3, .gpp23]
}

public enum VideoCodec: String, CaseIterable, Codable {
    case h264
    case hevc
}

public struct CompressionSettings: Codable, Equatable {
    public var targetValue: Double
    public var targetUnit: CompressionUnit
    public var allowResizeUpTo10x: Bool
    public var removeHDR: Bool
    public var outputFormatIdentifier: String?
    public var preferredResizeScale: Double?

    public init(
        targetValue: Double,
        targetUnit: CompressionUnit,
        allowResizeUpTo10x: Bool,
        removeHDR: Bool,
        outputFormatIdentifier: String?,
        preferredResizeScale: Double? = nil
    ) {
        self.targetValue = targetValue
        self.targetUnit = targetUnit
        self.allowResizeUpTo10x = allowResizeUpTo10x
        self.removeHDR = removeHDR
        self.outputFormatIdentifier = outputFormatIdentifier
        self.preferredResizeScale = preferredResizeScale
    }
}

public struct SourceVideoProfile: Equatable, Codable {
    public var durationSeconds: Double
    public var fileSizeBytes: Int64
    public var width: Int
    public var height: Int
    public var frameRate: Double
    public var hasHDR: Bool
    public var container: CompressionContainer
    public var codec: VideoCodec
    public var sourceVideoBitrate: Int
    public var sourceAudioBitrate: Int

    public init(
        durationSeconds: Double,
        fileSizeBytes: Int64,
        width: Int,
        height: Int,
        frameRate: Double,
        hasHDR: Bool,
        container: CompressionContainer,
        codec: VideoCodec,
        sourceVideoBitrate: Int,
        sourceAudioBitrate: Int
    ) {
        self.durationSeconds = durationSeconds
        self.fileSizeBytes = fileSizeBytes
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.hasHDR = hasHDR
        self.container = container
        self.codec = codec
        self.sourceVideoBitrate = sourceVideoBitrate
        self.sourceAudioBitrate = sourceAudioBitrate
    }
}

public struct CompressionPlan: Equatable {
    public var targetBytes: Int64
    public var outputContainer: CompressionContainer
    public var outputCodec: VideoCodec
    public var targetVideoBitrate: Int
    public var targetAudioBitrate: Int
    public var resizeScale: Double
    public var estimatedOutputBytes: Int64
    public var reason: String

    public init(
        targetBytes: Int64,
        outputContainer: CompressionContainer,
        outputCodec: VideoCodec,
        targetVideoBitrate: Int,
        targetAudioBitrate: Int,
        resizeScale: Double,
        estimatedOutputBytes: Int64,
        reason: String
    ) {
        self.targetBytes = targetBytes
        self.outputContainer = outputContainer
        self.outputCodec = outputCodec
        self.targetVideoBitrate = targetVideoBitrate
        self.targetAudioBitrate = targetAudioBitrate
        self.resizeScale = resizeScale
        self.estimatedOutputBytes = estimatedOutputBytes
        self.reason = reason
    }
}

public enum CompressionPlannerError: Error, Equatable, LocalizedError {
    case invalidTargetValue
    case invalidDuration
    case unsupportedRequestedFormat
    case compressionRatioExceeded(maxRatio: Double)

    public var errorDescription: String? {
        switch self {
        case .invalidTargetValue:
            return "Enter a valid positive target size."
        case .invalidDuration:
            return "The source video has an invalid duration."
        case .unsupportedRequestedFormat:
            return "The selected output format is not supported for this source."
        case .compressionRatioExceeded(let maxRatio):
            return "Target size exceeds max compression limit of \(Int(maxRatio))x."
        }
    }
}

public struct CompressionPlanner {
    public static let maxCompressionRatio: Double = 30
    public static let maxResizeReductionFactor: Double = 10
    private static let minVideoBitrate = 120_000
    private static let fallbackAudioBitrate = 96_000

    public init() {}

    public func bytes(for value: Double, unit: CompressionUnit) -> Int64 {
        Int64((value * unit.multiplier).rounded())
    }

    public func resolveOutputFormat(
        preferredIdentifier: String?,
        source: SourceVideoProfile,
        supported: [CompressionContainer]
    ) throws -> CompressionContainer {
        if let preferredIdentifier {
            let requested = CompressionContainer(identifier: preferredIdentifier)
            guard supported.contains(requested) else {
                throw CompressionPlannerError.unsupportedRequestedFormat
            }
            return requested
        }

        if supported.contains(source.container) {
            return source.container
        }

        for preferred in CompressionContainer.preferredAutoOrder where supported.contains(preferred) {
            return preferred
        }

        if let first = supported.first {
            return first
        }

        throw CompressionPlannerError.unsupportedRequestedFormat
    }

    public func makePlan(
        source: SourceVideoProfile,
        settings: CompressionSettings,
        supportedOutputFormats: [CompressionContainer]
    ) throws -> CompressionPlan {
        guard source.durationSeconds > 0 else {
            throw CompressionPlannerError.invalidDuration
        }

        let targetBytes = bytes(for: settings.targetValue, unit: settings.targetUnit)
        guard targetBytes > 0 else {
            throw CompressionPlannerError.invalidTargetValue
        }

        if source.fileSizeBytes > 0 {
            let minimumAllowedBytes = Int64(
                (Double(source.fileSizeBytes) / Self.maxCompressionRatio).rounded(.up)
            )
            if targetBytes < minimumAllowedBytes {
                throw CompressionPlannerError.compressionRatioExceeded(maxRatio: Self.maxCompressionRatio)
            }
        }

        let outputContainer = try resolveOutputFormat(
            preferredIdentifier: settings.outputFormatIdentifier,
            source: source,
            supported: supportedOutputFormats
        )

        let outputCodec: VideoCodec
        if settings.removeHDR && source.hasHDR {
            outputCodec = .h264
        } else {
            outputCodec = source.codec
        }

        let compressionRatio: Double
        if source.fileSizeBytes > 0 {
            compressionRatio = Double(source.fileSizeBytes) / Double(targetBytes)
        } else {
            compressionRatio = 1.0
        }
        let firstPassSafetyFactor = firstPassSafetyFactor(
            compressionRatio: compressionRatio,
            durationSeconds: source.durationSeconds
        )
        let totalBitrateBudget = max(
            Self.minVideoBitrate,
            Int((Double(targetBytes) * 8 / source.durationSeconds) * firstPassSafetyFactor)
        )
        var targetAudioBitrate = deriveAudioBitrate(
            sourceAudioBitrate: source.sourceAudioBitrate,
            totalBitrateBudget: totalBitrateBudget,
            compressionRatio: compressionRatio,
            durationSeconds: source.durationSeconds
        )
        var targetVideoBitrate = min(
            max(Self.minVideoBitrate, totalBitrateBudget - targetAudioBitrate),
            max(Self.minVideoBitrate, source.sourceVideoBitrate)
        )
        if targetVideoBitrate + targetAudioBitrate > totalBitrateBudget {
            targetVideoBitrate = max(Self.minVideoBitrate, totalBitrateBudget - targetAudioBitrate)
        }

        var resizeScale = 1.0
        if settings.allowResizeUpTo10x {
            resizeScale = recommendedResizeScale(
                source: source,
                targetVideoBitrate: targetVideoBitrate,
                removeHDR: settings.removeHDR
            )
            if let preferredScale = clampedPreferredScale(settings.preferredResizeScale) {
                resizeScale = min(resizeScale, preferredScale)
            }
        }
        // Safety guard: even with manual resize disabled, enforce a feasible scale for very low targets
        // to prevent encoder failures on high-resolution inputs.
        let safeScale = encoderSafetyScale(
            source: source,
            targetVideoBitrate: targetVideoBitrate,
            outputCodec: outputCodec,
            removeHDR: settings.removeHDR
        )
        resizeScale = min(resizeScale, safeScale)

        if compressionRatio >= 20 {
            let severity = min(1.0, max(0.0, (compressionRatio - 20) / 10))
            let videoFactor = 0.86 - (0.12 * severity)
            targetVideoBitrate = max(Self.minVideoBitrate, Int((Double(targetVideoBitrate) * videoFactor).rounded(.down)))

            if source.sourceAudioBitrate > 0 {
                let audioFloor = 24_000
                targetAudioBitrate = max(audioFloor, Int((Double(targetAudioBitrate) * 0.9).rounded(.down)))
            }

            let minScale = 1 / sqrt(Self.maxResizeReductionFactor)
            let scaleFactor = source.durationSeconds > 600 ? 0.84 : 0.90
            resizeScale = max(minScale, min(resizeScale, resizeScale * scaleFactor))
        }

        var estimatedBytes = estimateOutputBytes(
            videoBitrate: targetVideoBitrate,
            audioBitrate: targetAudioBitrate,
            durationSeconds: source.durationSeconds,
            container: outputContainer
        )

        while estimatedBytes > targetBytes && targetVideoBitrate > Self.minVideoBitrate {
            targetVideoBitrate = max(Self.minVideoBitrate, Int(Double(targetVideoBitrate) * 0.96))
            estimatedBytes = estimateOutputBytes(
                videoBitrate: targetVideoBitrate,
                audioBitrate: targetAudioBitrate,
                durationSeconds: source.durationSeconds,
                container: outputContainer
            )
        }

        while estimatedBytes > targetBytes && targetAudioBitrate > 32_000 {
            targetAudioBitrate = max(32_000, Int(Double(targetAudioBitrate) * 0.85))
            estimatedBytes = estimateOutputBytes(
                videoBitrate: targetVideoBitrate,
                audioBitrate: targetAudioBitrate,
                durationSeconds: source.durationSeconds,
                container: outputContainer
            )
        }

        if estimatedBytes > targetBytes {
            estimatedBytes = targetBytes
        }

        return CompressionPlan(
            targetBytes: targetBytes,
            outputContainer: outputContainer,
            outputCodec: outputCodec,
            targetVideoBitrate: targetVideoBitrate,
            targetAudioBitrate: targetAudioBitrate,
            resizeScale: resizeScale,
            estimatedOutputBytes: estimatedBytes,
            reason: "Initial plan based on target size budget"
        )
    }

    public func makeRetryPlan(
        source: SourceVideoProfile,
        priorPlan: CompressionPlan,
        settings: CompressionSettings,
        supportedOutputFormats: [CompressionContainer]
    ) throws -> CompressionPlan {
        let basePlan = try makePlan(
            source: source,
            settings: settings,
            supportedOutputFormats: supportedOutputFormats
        )

        let targetBytes = basePlan.targetBytes
        let outputContainer = basePlan.outputContainer
        let outputCodec = basePlan.outputCodec

        var targetVideoBitrate = min(
            basePlan.targetVideoBitrate,
            max(Self.minVideoBitrate, Int(Double(priorPlan.targetVideoBitrate) * 0.85))
        )
        var targetAudioBitrate = min(basePlan.targetAudioBitrate, priorPlan.targetAudioBitrate)
        var resizeScale = priorPlan.resizeScale
        if settings.allowResizeUpTo10x {
            let minScale = 1 / sqrt(Self.maxResizeReductionFactor)
            resizeScale = max(minScale, min(priorPlan.resizeScale, priorPlan.resizeScale * 0.9))
            if let preferredScale = clampedPreferredScale(settings.preferredResizeScale) {
                resizeScale = min(resizeScale, preferredScale)
            }
        }
        let safeScale = encoderSafetyScale(
            source: source,
            targetVideoBitrate: targetVideoBitrate,
            outputCodec: outputCodec,
            removeHDR: settings.removeHDR
        )
        resizeScale = min(resizeScale, safeScale)

        var estimatedBytes = estimateOutputBytes(
            videoBitrate: targetVideoBitrate,
            audioBitrate: targetAudioBitrate,
            durationSeconds: source.durationSeconds,
            container: outputContainer
        )

        while estimatedBytes > targetBytes && targetVideoBitrate > Self.minVideoBitrate {
            targetVideoBitrate = max(Self.minVideoBitrate, Int(Double(targetVideoBitrate) * 0.92))
            estimatedBytes = estimateOutputBytes(
                videoBitrate: targetVideoBitrate,
                audioBitrate: targetAudioBitrate,
                durationSeconds: source.durationSeconds,
                container: outputContainer
            )
        }

        while estimatedBytes > targetBytes && targetAudioBitrate > 32_000 {
            targetAudioBitrate = max(32_000, Int(Double(targetAudioBitrate) * 0.85))
            estimatedBytes = estimateOutputBytes(
                videoBitrate: targetVideoBitrate,
                audioBitrate: targetAudioBitrate,
                durationSeconds: source.durationSeconds,
                container: outputContainer
            )
        }

        if estimatedBytes > targetBytes {
            estimatedBytes = targetBytes
        }

        return CompressionPlan(
            targetBytes: targetBytes,
            outputContainer: outputContainer,
            outputCodec: outputCodec,
            targetVideoBitrate: targetVideoBitrate,
            targetAudioBitrate: targetAudioBitrate,
            resizeScale: resizeScale,
            estimatedOutputBytes: estimatedBytes,
            reason: "Retry plan reduced bitrate/scale to guarantee target"
        )
    }

    public static func generateSourceCombinations(
        durations: [Double],
        resolutions: [(Int, Int)],
        hdrStates: [Bool],
        containers: [CompressionContainer],
        codecs: [VideoCodec]
    ) -> [SourceVideoProfile] {
        var out: [SourceVideoProfile] = []
        for duration in durations {
            for resolution in resolutions {
                for hdr in hdrStates {
                    for container in containers {
                        for codec in codecs {
                            let width = resolution.0
                            let height = resolution.1
                            let pixels = Double(width * height)
                            let bitrate = Int(max(400_000, min(40_000_000, pixels * 2.2)))
                            let audio = duration > 0 ? 128_000 : 0
                            let bytes = Int64(Double(bitrate + audio) * max(duration, 1) / 8)
                            out.append(
                                SourceVideoProfile(
                                    durationSeconds: duration,
                                    fileSizeBytes: bytes,
                                    width: width,
                                    height: height,
                                    frameRate: 30,
                                    hasHDR: hdr,
                                    container: container,
                                    codec: codec,
                                    sourceVideoBitrate: bitrate,
                                    sourceAudioBitrate: audio
                                )
                            )
                        }
                    }
                }
            }
        }
        return out
    }

    private func deriveAudioBitrate(
        sourceAudioBitrate: Int,
        totalBitrateBudget: Int,
        compressionRatio: Double,
        durationSeconds: Double
    ) -> Int {
        let aggressiveMode = compressionRatio >= 24 || durationSeconds >= 900
        let ultraAggressiveMode = compressionRatio >= 28

        let budgetDivisor: Int
        let cap: Int
        let floor: Int
        if ultraAggressiveMode {
            budgetDivisor = 9
            cap = 40_000
            floor = 20_000
        } else if aggressiveMode {
            budgetDivisor = 8
            cap = 48_000
            floor = 24_000
        } else {
            budgetDivisor = 6
            cap = 192_000
            floor = 32_000
        }

        if sourceAudioBitrate <= 0 {
            return min(Self.fallbackAudioBitrate, max(floor, totalBitrateBudget / budgetDivisor))
        }

        let cappedSource = min(sourceAudioBitrate, cap)
        let budgetLimited = max(floor, totalBitrateBudget / budgetDivisor)
        return min(cappedSource, budgetLimited)
    }

    private func recommendedResizeScale(
        source: SourceVideoProfile,
        targetVideoBitrate: Int,
        removeHDR: Bool
    ) -> Double {
        let hdrPenalty = source.hasHDR && !removeHDR
        let bpp = hdrPenalty ? 0.10 : 0.07
        let rawQualityBitrate = Double(source.width * source.height) * source.frameRate * bpp
        guard rawQualityBitrate > 0 else { return 1.0 }

        let ratio = Double(targetVideoBitrate) / rawQualityBitrate
        if ratio >= 1 {
            return 1.0
        }

        let minScale = 1 / sqrt(Self.maxResizeReductionFactor)
        return max(minScale, min(1.0, sqrt(max(0.01, ratio))))
    }

    private func encoderSafetyScale(
        source: SourceVideoProfile,
        targetVideoBitrate: Int,
        outputCodec: VideoCodec,
        removeHDR: Bool
    ) -> Double {
        let width = Double(max(1, source.width))
        let height = Double(max(1, source.height))
        let fps = max(24.0, source.frameRate)

        let baseMinBPP: Double
        switch outputCodec {
        case .h264:
            baseMinBPP = 0.028
        case .hevc:
            baseMinBPP = 0.020
        }

        let hdrMultiplier = (source.hasHDR && !removeHDR) ? 1.2 : 1.0
        let minBPP = baseMinBPP * hdrMultiplier
        let denominator = width * height * fps * minBPP
        guard denominator > 0 else {
            return 1.0
        }

        let ratio = Double(max(targetVideoBitrate, Self.minVideoBitrate)) / denominator
        if ratio >= 1 {
            return 1.0
        }

        let minScale = 1 / sqrt(Self.maxResizeReductionFactor)
        return max(minScale, min(1.0, sqrt(max(0.01, ratio))))
    }

    private func estimateOutputBytes(
        videoBitrate: Int,
        audioBitrate: Int,
        durationSeconds: Double,
        container: CompressionContainer
    ) -> Int64 {
        let muxOverhead: Double
        if container == .mov {
            muxOverhead = 1.020
        } else if container == .mp4 || container == .m4v || container == .gpp3 || container == .gpp23 {
            muxOverhead = 1.015
        } else {
            muxOverhead = 1.018
        }
        let payloadBits = Double(max(0, videoBitrate + audioBitrate)) * max(durationSeconds, 0)
        let bytes = (payloadBits / 8) * muxOverhead
        return Int64(bytes.rounded(.up))
    }

    private func clampedPreferredScale(_ value: Double?) -> Double? {
        guard let value else { return nil }
        let minScale = 1 / sqrt(Self.maxResizeReductionFactor)
        return max(minScale, min(1.0, value))
    }

    private func firstPassSafetyFactor(
        compressionRatio: Double,
        durationSeconds: Double
    ) -> Double {
        let clampedRatio = max(1.0, min(Self.maxCompressionRatio, compressionRatio))
        let normalizedRatio = (clampedRatio - 1.0) / (Self.maxCompressionRatio - 1.0)

        // Higher ratios are more likely to overshoot in real encoders, so reserve headroom.
        var ratioPenalty = normalizedRatio * 0.22
        if clampedRatio >= 24 {
            ratioPenalty += min(0.04, ((clampedRatio - 24) / 6) * 0.04)
        }

        // Very long clips can fluctuate bitrate significantly; add a small extra guard band.
        let longDurationPenalty: Double
        if durationSeconds > 480 {
            longDurationPenalty = min(0.07, ((durationSeconds - 480) / 2520) * 0.07)
        } else {
            longDurationPenalty = 0
        }

        return max(0.62, min(0.985, 0.985 - ratioPenalty - longDurationPenalty))
    }
}
