import Foundation
import Testing
@testable import CompressionPlanner

struct CompressionPlannerTests {
    private let planner = CompressionPlanner()

    @Test
    func bytesConversion() {
        #expect(planner.bytes(for: 1, unit: .kb) == 1_024)
        #expect(planner.bytes(for: 1.5, unit: .mb) == 1_572_864)
        #expect(planner.bytes(for: 1, unit: .gb) == 1_073_741_824)
    }

    @Test
    func resolveAutoKeepsSourceWhenSupported() throws {
        let source = makeSource(container: .mov)
        let resolved = try planner.resolveOutputFormat(
            preferredIdentifier: nil,
            source: source,
            supported: [.mov, .mp4]
        )
        #expect(resolved == .mov)
    }

    @Test
    func resolveAutoFallsBackToMP4() throws {
        let source = makeSource(container: .m4v)
        let resolved = try planner.resolveOutputFormat(
            preferredIdentifier: nil,
            source: source,
            supported: [.mp4, .mov]
        )
        #expect(resolved == .mp4)
    }

    @Test
    func resolveExplicitSupportsDynamicIdentifiers() throws {
        let dynamicContainer = CompressionContainer(identifier: "com.example.custom-video-container")
        let source = makeSource(container: .mov)
        let resolved = try planner.resolveOutputFormat(
            preferredIdentifier: dynamicContainer.identifier,
            source: source,
            supported: [.mov, dynamicContainer]
        )

        #expect(resolved == dynamicContainer)
    }

    @Test
    func resolveExplicitUnsupportedIdentifierThrows() {
        let source = makeSource(container: .mov)

        #expect(throws: CompressionPlannerError.unsupportedRequestedFormat) {
            try planner.resolveOutputFormat(
                preferredIdentifier: "com.example.unsupported",
                source: source,
                supported: [.mov, .mp4]
            )
        }
    }

    @Test
    func makePlanRejectsMoreThanThirtyXCompression() {
        let source = makeSource(bytes: 300 * 1_024 * 1_024)
        let settings = CompressionSettings(
            targetValue: 5,
            targetUnit: .mb,
            allowResizeUpTo10x: false,
            removeHDR: false,
            outputFormatIdentifier: nil
        )

        #expect(throws: CompressionPlannerError.compressionRatioExceeded(maxRatio: 30)) {
            try planner.makePlan(source: source, settings: settings, supportedOutputFormats: [.mov, .mp4])
        }
    }

    @Test
    func makePlanRespectsTargetAndHighestQualityBoundary() throws {
        let source = makeSource(
            duration: 20,
            bytes: 120 * 1_024 * 1_024,
            width: 1920,
            height: 1080,
            sourceBitrate: 20_000_000,
            audioBitrate: 192_000
        )
        let settings = CompressionSettings(
            targetValue: 25,
            targetUnit: .mb,
            allowResizeUpTo10x: false,
            removeHDR: false,
            outputFormatIdentifier: nil
        )

        let plan = try planner.makePlan(source: source, settings: settings, supportedOutputFormats: [.mov, .mp4])

        #expect(plan.estimatedOutputBytes <= plan.targetBytes)
        #expect(plan.targetVideoBitrate > 0)
        #expect(plan.targetVideoBitrate <= source.sourceVideoBitrate)
    }

    @Test
    func retryPlanFurtherReducesSizeAndKeepsAtOrBelowTarget() throws {
        let source = makeSource(
            duration: 45,
            bytes: 400 * 1_024 * 1_024,
            width: 3840,
            height: 2160,
            sourceBitrate: 45_000_000,
            audioBitrate: 192_000
        )
        let settings = CompressionSettings(
            targetValue: 50,
            targetUnit: .mb,
            allowResizeUpTo10x: true,
            removeHDR: false,
            outputFormatIdentifier: nil
        )

        let first = try planner.makePlan(source: source, settings: settings, supportedOutputFormats: [.mov, .mp4])
        let retry = try planner.makeRetryPlan(
            source: source,
            priorPlan: first,
            settings: settings,
            supportedOutputFormats: [.mov, .mp4]
        )

        #expect(retry.estimatedOutputBytes <= retry.targetBytes)
        #expect(retry.targetVideoBitrate <= first.targetVideoBitrate)
        #expect(retry.resizeScale <= first.resizeScale)
    }

    @Test
    func removeHDRForcesH264() throws {
        let source = makeSource(codec: .hevc, hdr: true)
        let settings = CompressionSettings(
            targetValue: 40,
            targetUnit: .mb,
            allowResizeUpTo10x: true,
            removeHDR: true,
            outputFormatIdentifier: nil
        )

        let plan = try planner.makePlan(source: source, settings: settings, supportedOutputFormats: [.mov, .mp4])
        #expect(plan.outputCodec == .h264)
    }

    @Test
    func preferredResizeScaleCapsInitialPlan() throws {
        let source = makeSource(
            duration: 45,
            bytes: 300 * 1_024 * 1_024,
            width: 3840,
            height: 2160,
            sourceBitrate: 38_000_000
        )
        let settings = CompressionSettings(
            targetValue: 45,
            targetUnit: .mb,
            allowResizeUpTo10x: true,
            removeHDR: false,
            outputFormatIdentifier: nil,
            preferredResizeScale: 0.5
        )

        let plan = try planner.makePlan(source: source, settings: settings, supportedOutputFormats: [.mov, .mp4])
        #expect(plan.resizeScale <= 0.5)
    }

    @Test
    func preferredResizeScaleCapsRetryPlan() throws {
        let source = makeSource(
            duration: 60,
            bytes: 500 * 1_024 * 1_024,
            width: 3840,
            height: 2160,
            sourceBitrate: 45_000_000
        )
        let settings = CompressionSettings(
            targetValue: 70,
            targetUnit: .mb,
            allowResizeUpTo10x: true,
            removeHDR: false,
            outputFormatIdentifier: nil,
            preferredResizeScale: 0.4
        )

        let first = try planner.makePlan(source: source, settings: settings, supportedOutputFormats: [.mov, .mp4])
        let retry = try planner.makeRetryPlan(
            source: source,
            priorPlan: first,
            settings: settings,
            supportedOutputFormats: [.mov, .mp4]
        )

        #expect(first.resizeScale <= 0.4)
        #expect(retry.resizeScale <= 0.4)
    }

    @Test
    func sourceCombinationMatrixAlwaysProducesValidPlan() throws {
        let matrixContainers: [CompressionContainer] = [.mov, .mp4, .m4v, .gpp3, .gpp23]
        let sources = CompressionPlanner.generateSourceCombinations(
            durations: [5, 30, 60, 120],
            resolutions: [(1280, 720), (1920, 1080), (3840, 2160)],
            hdrStates: [false, true],
            containers: matrixContainers,
            codecs: [.h264, .hevc]
        )

        #expect(sources.count == 240)

        let settings = CompressionSettings(
            targetValue: 30,
            targetUnit: .mb,
            allowResizeUpTo10x: true,
            removeHDR: false,
            outputFormatIdentifier: nil
        )

        for source in sources {
            let plan = try planner.makePlan(source: source, settings: settings, supportedOutputFormats: matrixContainers)
            #expect(plan.estimatedOutputBytes <= plan.targetBytes)
            #expect(plan.resizeScale > 0)
            #expect(plan.resizeScale <= 1)
            #expect(matrixContainers.contains(plan.outputContainer))
        }
    }

    @Test
    func generatedDatasetManifestProducesValidPlans() throws {
        let manifestPath = "/Users/test/XCodeProjects/CompressTarget_data/manifest.csv"
        #expect(FileManager.default.fileExists(atPath: manifestPath))

        let content = try String(contentsOfFile: manifestPath, encoding: .utf8)
        let rows = content.split(separator: "\n").dropFirst()
        #expect(rows.count >= 60)

        let settings = CompressionSettings(
            targetValue: 60,
            targetUnit: .mb,
            allowResizeUpTo10x: true,
            removeHDR: false,
            outputFormatIdentifier: nil
        )

        for row in rows {
            let parts = row.split(separator: ",").map(String.init)
            #expect(parts.count == 7)

            guard parts.count == 7 else { continue }
            let codec: VideoCodec = parts[1] == "hevc" ? .hevc : .h264
            let hdr = parts[2] == "hdr"
            let container = parseContainer(parts[3])
            let resolution = parts[4].split(separator: "x")
            let width = Int(resolution.first ?? "1920") ?? 1920
            let height = Int(resolution.last ?? "1080") ?? 1080
            let duration = Double(parts[5]) ?? 30
            let sizeBytes = Int64(parts[6]) ?? Int64(50 * 1_024 * 1_024)
            let estimatedTotalBitrate = Int((Double(sizeBytes) * 8) / max(duration, 1))
            let audioBitrate = 128_000
            let videoBitrate = max(300_000, estimatedTotalBitrate - audioBitrate)

            let source = SourceVideoProfile(
                durationSeconds: duration,
                fileSizeBytes: sizeBytes,
                width: width,
                height: height,
                frameRate: 30,
                hasHDR: hdr,
                container: container,
                codec: codec,
                sourceVideoBitrate: videoBitrate,
                sourceAudioBitrate: audioBitrate
            )

            let supportedFormats = Array(Set([container, .mov, .mp4, .m4v, .gpp3, .gpp23]))
            let plan = try planner.makePlan(
                source: source,
                settings: settings,
                supportedOutputFormats: supportedFormats
            )
            #expect(plan.estimatedOutputBytes <= plan.targetBytes)
            #expect(plan.resizeScale > 0)
            #expect(plan.resizeScale <= 1)
        }
    }

    private func makeSource(
        duration: Double = 20,
        bytes: Int64 = 80 * 1_024 * 1_024,
        width: Int = 1920,
        height: Int = 1080,
        codec: VideoCodec = .hevc,
        hdr: Bool = false,
        container: CompressionContainer = .mov,
        sourceBitrate: Int = 12_000_000,
        audioBitrate: Int = 128_000
    ) -> SourceVideoProfile {
        SourceVideoProfile(
            durationSeconds: duration,
            fileSizeBytes: bytes,
            width: width,
            height: height,
            frameRate: 30,
            hasHDR: hdr,
            container: container,
            codec: codec,
            sourceVideoBitrate: sourceBitrate,
            sourceAudioBitrate: audioBitrate
        )
    }

    private func parseContainer(_ token: String) -> CompressionContainer {
        switch token.lowercased() {
        case "mov":
            return .mov
        case "mp4":
            return .mp4
        case "m4v":
            return .m4v
        case "3gp":
            return .gpp3
        case "3g2":
            return .gpp23
        default:
            return CompressionContainer(identifier: token)
        }
    }
}
