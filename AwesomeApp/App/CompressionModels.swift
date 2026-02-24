import AVFoundation
import CoreMedia
import Foundation
import UniformTypeIdentifiers

struct VideoMetadata: Equatable {
    let sourceURL: URL
    let durationSeconds: Double
    let fileSizeBytes: Int64
    let width: Int
    let height: Int
    let frameRate: Double
    let hasHDR: Bool
    let container: CompressionContainer
    let codec: VideoCodec
    let sourceVideoBitrate: Int
    let sourceAudioBitrate: Int
    let preferredTransform: CGAffineTransform

    var sourceProfile: SourceVideoProfile {
        SourceVideoProfile(
            durationSeconds: durationSeconds,
            fileSizeBytes: fileSizeBytes,
            width: width,
            height: height,
            frameRate: frameRate,
            hasHDR: hasHDR,
            container: container,
            codec: codec,
            sourceVideoBitrate: sourceVideoBitrate,
            sourceAudioBitrate: sourceAudioBitrate
        )
    }
}

struct OutputFormatOption: Identifiable, Hashable {
    static let autoID = "auto"

    let id: String
    let title: String

    var isAuto: Bool {
        id == Self.autoID
    }
}

struct ResolutionOption: Identifiable, Hashable {
    let id: String
    let title: String
    let scale: Double
}

enum CompressionModelError: LocalizedError {
    case noVideoTrack
    case unsupportedOutputFormat

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            L10n.tr("The selected file does not contain a video track.")
        case .unsupportedOutputFormat:
            L10n.tr("Unable to determine a supported output format for this file.")
        }
    }
}

extension CompressionContainer {
    static let genericMovie = CompressionContainer(identifier: UTType.movie.identifier)

    var avFileType: AVFileType {
        AVFileType(rawValue: identifier)
    }

    var fileExtension: String {
        switch identifier {
        case CompressionContainer.mov.identifier:
            return "mov"
        case CompressionContainer.mp4.identifier:
            return "mp4"
        case CompressionContainer.m4v.identifier:
            return "m4v"
        case CompressionContainer.gpp3.identifier:
            return "3gp"
        case CompressionContainer.gpp23.identifier:
            return "3g2"
        default:
            if let ext = UTType(identifier)?.preferredFilenameExtension {
                return ext
            }
            return identifier
                .split(separator: ".")
                .last
                .map(String.init)
                ?? "mov"
        }
    }

    var label: String {
        if self == .mov { return "MOV" }
        if self == .mp4 { return "MP4" }
        if self == .m4v { return "M4V" }
        if self == .gpp3 { return "3GP" }
        if self == .gpp23 { return "3G2" }
        return fileExtension.uppercased()
    }

    init(fileType: AVFileType) {
        self = CompressionContainer(identifier: fileType.rawValue)
    }

    init(url: URL) {
        let ext = url.pathExtension.lowercased()
        if let utType = UTType(filenameExtension: ext) {
            self = CompressionContainer(identifier: utType.identifier)
            return
        }

        switch ext {
        case "mov":
            self = .mov
        case "mp4":
            self = .mp4
        case "m4v":
            self = .m4v
        case "3gp":
            self = .gpp3
        case "3g2":
            self = .gpp23
        default:
            self = .genericMovie
        }
    }
}

extension VideoCodec {
    var avVideoCodecType: AVVideoCodecType {
        switch self {
        case .h264:
            .h264
        case .hevc:
            .hevc
        }
    }

    static func from(formatDescription: CMFormatDescription?) -> VideoCodec {
        guard let formatDescription else {
            return .h264
        }

        switch CMFormatDescriptionGetMediaSubType(formatDescription) {
        case kCMVideoCodecType_HEVC:
            return .hevc
        default:
            return .h264
        }
    }
}

extension CompressionUnit {
    var label: String {
        switch self {
        case .kb:
            "KB"
        case .mb:
            "MB"
        case .gb:
            "GB"
        }
    }
}

func makeEven(_ value: Int) -> Int {
    let minValue = max(64, value)
    return minValue.isMultiple(of: 2) ? minValue : minValue - 1
}

func humanReadableSize(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
