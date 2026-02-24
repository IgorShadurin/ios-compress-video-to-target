import AVFoundation
import Foundation

enum VideoCompressionServiceError: LocalizedError {
    case cannotCreateReader
    case cannotCreateWriter
    case cannotAddVideoOutput
    case cannotAddVideoInput
    case cannotAddAudioOutput
    case cannotAddAudioInput
    case startReadingFailed
    case startWritingFailed
    case appendFailed(String)
    case noFinalOutput
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cannotCreateReader:
            L10n.tr("Unable to initialize AVAssetReader.")
        case .cannotCreateWriter:
            L10n.tr("Unable to initialize AVAssetWriter.")
        case .cannotAddVideoOutput:
            L10n.tr("Unable to add video output reader.")
        case .cannotAddVideoInput:
            L10n.tr("Unable to add video writer input.")
        case .cannotAddAudioOutput:
            L10n.tr("Unable to add audio output reader.")
        case .cannotAddAudioInput:
            L10n.tr("Unable to add audio writer input.")
        case .startReadingFailed:
            L10n.tr("Failed to start reading source video.")
        case .startWritingFailed:
            L10n.tr("Failed to start writing output video.")
        case .appendFailed(let mediaType):
            L10n.fmt("Failed while appending %@ samples.", mediaType)
        case .noFinalOutput:
            L10n.tr("Compression finished without producing an output file.")
        case .cancelled:
            L10n.tr("Conversion was cancelled.")
        }
    }
}

final class VideoCompressionService {
    private struct ActiveCompression {
        let reader: AVAssetReader
        let writer: AVAssetWriter
        let outputURL: URL
    }

    private final class ErrorBox {
        private let lock = NSLock()
        private var storedError: Error?

        func setIfEmpty(_ error: Error) {
            lock.lock()
            defer { lock.unlock() }
            if storedError == nil {
                storedError = error
            }
        }

        var error: Error? {
            lock.lock()
            defer { lock.unlock() }
            return storedError
        }
    }

    private let activeCompressionLock = NSLock()
    private var activeCompression: ActiveCompression?

    func cancelCurrentCompression() {
        let operation: ActiveCompression? = {
            activeCompressionLock.lock()
            defer { activeCompressionLock.unlock() }
            return activeCompression
        }()

        guard let operation else { return }

        operation.reader.cancelReading()
        operation.writer.cancelWriting()
        try? FileManager.default.removeItem(at: operation.outputURL)
    }

    func compress(
        sourceURL: URL,
        metadata: VideoMetadata,
        plan: CompressionPlan,
        removeHDR: Bool,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> URL {
        let outputURL = makeOutputURL(container: plan.outputContainer)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw CompressionModelError.noVideoTrack
        }

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let reader = try? AVAssetReader(asset: asset) else {
            throw VideoCompressionServiceError.cannotCreateReader
        }

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: plan.outputContainer.avFileType) else {
            throw VideoCompressionServiceError.cannotCreateWriter
        }
        registerActiveCompression(reader: reader, writer: writer, outputURL: outputURL)
        defer { clearActiveCompression(outputURL: outputURL) }

        let outputSize = calculateOutputSize(
            width: metadata.width,
            height: metadata.height,
            scale: plan.resizeScale
        )

        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: plan.targetVideoBitrate,
            AVVideoMaxKeyFrameIntervalDurationKey: 2.0,
            AVVideoExpectedSourceFrameRateKey: Int(max(1, metadata.frameRate.rounded()))
        ]

        switch plan.outputCodec {
        case .h264:
            compressionProperties[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        case .hevc:
            break
        }

        var videoSettings: [String: Any] = [
            AVVideoCodecKey: plan.outputCodec.avVideoCodecType,
            AVVideoWidthKey: outputSize.width,
            AVVideoHeightKey: outputSize.height,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]

        if removeHDR {
            videoSettings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        }

        let videoOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        ]

        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoOutputSettings)
        videoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(videoOutput) else {
            throw VideoCompressionServiceError.cannotAddVideoOutput
        }
        reader.add(videoOutput)

        var finalVideoSettings = videoSettings
        if !writer.canApply(outputSettings: finalVideoSettings, forMediaType: .video) {
            finalVideoSettings[AVVideoCodecKey] = AVVideoCodecType.h264
        }

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: finalVideoSettings)
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = metadata.preferredTransform
        guard writer.canAdd(videoInput) else {
            throw VideoCompressionServiceError.cannotAddVideoInput
        }
        writer.add(videoInput)

        var audioOutput: AVAssetReaderTrackOutput?
        var audioInput: AVAssetWriterInput?

        if let audioTrack = audioTracks.first {
            let readerAudioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let candidateAudioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerAudioSettings)
            candidateAudioOutput.alwaysCopiesSampleData = false
            guard reader.canAdd(candidateAudioOutput) else {
                throw VideoCompressionServiceError.cannotAddAudioOutput
            }
            reader.add(candidateAudioOutput)
            audioOutput = candidateAudioOutput

            let sourceAudioParameters = try await extractSourceAudioParameters(from: audioTrack)
            let normalizedChannelCount = min(max(sourceAudioParameters.channels, 1), 2)
            let normalizedSampleRate = min(max(sourceAudioParameters.sampleRate, 22_050), 48_000)
            let maxAllowedBitrate = normalizedChannelCount == 1 ? 128_000 : 192_000
            let minAllowedBitrate = normalizedChannelCount == 1 ? 24_000 : 32_000

            var audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: normalizedSampleRate,
                AVNumberOfChannelsKey: normalizedChannelCount,
                AVEncoderBitRateKey: max(minAllowedBitrate, min(plan.targetAudioBitrate, maxAllowedBitrate))
            ]

            if !writer.canApply(outputSettings: audioSettings, forMediaType: .audio) {
                audioSettings = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44_100,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: max(32_000, min(plan.targetAudioBitrate, 128_000))
                ]
            }

            let candidateAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            candidateAudioInput.expectsMediaDataInRealTime = false
            guard writer.canAdd(candidateAudioInput) else {
                throw VideoCompressionServiceError.cannotAddAudioInput
            }
            writer.add(candidateAudioInput)
            audioInput = candidateAudioInput
        }

        guard reader.startReading() else {
            throw reader.error ?? VideoCompressionServiceError.startReadingFailed
        }

        guard writer.startWriting() else {
            throw writer.error ?? VideoCompressionServiceError.startWritingFailed
        }

        writer.startSession(atSourceTime: .zero)

        progressHandler?(0)

        return try await withCheckedThrowingContinuation { continuation in
            let errorBox = ErrorBox()
            let group = DispatchGroup()
            let durationSeconds = max(metadata.durationSeconds, 0.001)

            group.enter()
            pumpSamples(
                output: videoOutput,
                input: videoInput,
                mediaType: "video",
                queueLabel: "video-compress-queue",
                group: group,
                reader: reader,
                writer: writer,
                errorBox: errorBox,
                durationSeconds: durationSeconds,
                progressHandler: progressHandler
            )

            if let audioOutput, let audioInput {
                group.enter()
                pumpSamples(
                    output: audioOutput,
                    input: audioInput,
                    mediaType: "audio",
                    queueLabel: "audio-compress-queue",
                    group: group,
                    reader: reader,
                    writer: writer,
                    errorBox: errorBox,
                    durationSeconds: nil,
                    progressHandler: nil
                )
            }

            group.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
                if let processError = errorBox.error {
                    reader.cancelReading()
                    writer.cancelWriting()
                    continuation.resume(throwing: processError)
                    return
                }

                if reader.status == .cancelled || writer.status == .cancelled {
                    try? FileManager.default.removeItem(at: outputURL)
                    continuation.resume(throwing: VideoCompressionServiceError.cancelled)
                    return
                }

                if reader.status == .failed {
                    writer.cancelWriting()
                    continuation.resume(throwing: reader.error ?? VideoCompressionServiceError.appendFailed("reader"))
                    return
                }

                writer.finishWriting {
                    if writer.status == .failed {
                        continuation.resume(throwing: writer.error ?? VideoCompressionServiceError.appendFailed("writer"))
                        return
                    }

                    guard FileManager.default.fileExists(atPath: outputURL.path) else {
                        continuation.resume(throwing: VideoCompressionServiceError.noFinalOutput)
                        return
                    }

                    progressHandler?(1)
                    continuation.resume(returning: outputURL)
                }
            }
        }
    }

    private func pumpSamples(
        output: AVAssetReaderOutput,
        input: AVAssetWriterInput,
        mediaType: String,
        queueLabel: String,
        group: DispatchGroup,
        reader: AVAssetReader,
        writer: AVAssetWriter,
        errorBox: ErrorBox,
        durationSeconds: Double?,
        progressHandler: ((Double) -> Void)?
    ) {
        let queue = DispatchQueue(label: queueLabel, qos: .userInitiated)
        var didFinish = false
        var lastPTS = CMTime.invalid
        var lastReportedProgress: Double = -1

        input.requestMediaDataWhenReady(on: queue) {
            if didFinish {
                return
            }

            while input.isReadyForMoreMediaData {
                if reader.status == .cancelled || writer.status == .cancelled {
                    errorBox.setIfEmpty(VideoCompressionServiceError.cancelled)
                    input.markAsFinished()
                    didFinish = true
                    group.leave()
                    return
                }

                if writer.status != .writing {
                    let baseError = writer.error ?? reader.error ?? VideoCompressionServiceError.appendFailed(mediaType)
                    errorBox.setIfEmpty(baseError)
                    input.markAsFinished()
                    didFinish = true
                    group.leave()
                    return
                }

                if let sample = output.copyNextSampleBuffer() {
                    guard CMSampleBufferDataIsReady(sample) else {
                        continue
                    }

                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    guard pts.isValid && !pts.isIndefinite else {
                        continue
                    }

                    if lastPTS.isValid, CMTimeCompare(pts, lastPTS) < 0 {
                        continue
                    }

                    if !input.append(sample) {
                        let baseError = writer.error ?? reader.error ?? VideoCompressionServiceError.appendFailed(mediaType)
                        errorBox.setIfEmpty(baseError)
                        input.markAsFinished()
                        didFinish = true
                        group.leave()
                        return
                    }
                    lastPTS = pts

                    if let durationSeconds,
                       let progressHandler
                    {
                        let sampleSeconds = CMTimeGetSeconds(pts)
                        guard sampleSeconds.isFinite else {
                            continue
                        }
                        let progress = min(max(sampleSeconds / durationSeconds, 0), 1)
                        if progress >= 0.999 || progress - lastReportedProgress >= 0.01 {
                            lastReportedProgress = progress
                            progressHandler(progress)
                        }
                    }
                } else {
                    input.markAsFinished()
                    if let progressHandler, durationSeconds != nil {
                        progressHandler(1)
                    }
                    didFinish = true
                    group.leave()
                    return
                }
            }
        }
    }

    private func calculateOutputSize(width: Int, height: Int, scale: Double) -> (width: Int, height: Int) {
        let clampedScale = min(max(scale, 1 / sqrt(CompressionPlanner.maxResizeReductionFactor)), 1)
        let scaledWidth = makeEven(Int((Double(width) * clampedScale).rounded()))
        let scaledHeight = makeEven(Int((Double(height) * clampedScale).rounded()))
        return (width: scaledWidth, height: scaledHeight)
    }

    private func makeOutputURL(container: CompressionContainer) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("compressed-\(UUID().uuidString)")
            .appendingPathExtension(container.fileExtension)
    }

    private func extractSourceAudioParameters(from track: AVAssetTrack) async throws -> (sampleRate: Double, channels: Int) {
        let formatDescriptions = try await track.load(.formatDescriptions)
        for description in formatDescriptions {
            let audioDescription = description as CMAudioFormatDescription
            guard let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(audioDescription) else {
                continue
            }
            let sampleRate = streamDescription.pointee.mSampleRate
            let channels = Int(streamDescription.pointee.mChannelsPerFrame)
            if sampleRate > 0, channels > 0 {
                return (sampleRate, channels)
            }
        }
        return (44_100, 2)
    }

    private func registerActiveCompression(reader: AVAssetReader, writer: AVAssetWriter, outputURL: URL) {
        activeCompressionLock.lock()
        activeCompression = ActiveCompression(reader: reader, writer: writer, outputURL: outputURL)
        activeCompressionLock.unlock()
    }

    private func clearActiveCompression(outputURL: URL) {
        activeCompressionLock.lock()
        defer { activeCompressionLock.unlock() }
        guard let activeCompression, activeCompression.outputURL == outputURL else {
            return
        }
        self.activeCompression = nil
    }
}
