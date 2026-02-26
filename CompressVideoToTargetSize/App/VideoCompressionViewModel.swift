import AVFoundation
import Combine
import Foundation
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class VideoCompressionViewModel: ObservableObject {
    private enum ShowcaseStep: String {
        case source
        case settings
        case convert
    }

    private enum SourceLoadError: LocalizedError {
        case noVideoSelected
        case unsupportedSelection

        var errorDescription: String? {
            switch self {
            case .noVideoSelected:
                return L10n.tr("No video was selected.")
            case .unsupportedSelection:
                return L10n.tr("Please select a video from Gallery.")
            }
        }
    }

    private enum ConversionTargetError: LocalizedError {
        case unableToReachTarget(targetBytes: Int64, bestBytes: Int64)
        case audioTrackMissingInOutput

        var errorDescription: String? {
            switch self {
            case let .unableToReachTarget(targetBytes, bestBytes):
                return L10n.fmt(
                    "Could not reach target size %@. Best result was %@.",
                    humanReadableSize(targetBytes),
                    humanReadableSize(bestBytes)
                )
            case .audioTrackMissingInOutput:
                return L10n.tr("Converted video lost audio track. Please try again with a different target size.")
            }
        }
    }

    enum WorkflowStep: Int, CaseIterable {
        case source = 1
        case settings = 2
        case conversion = 3

        var shortTitle: String {
            switch self {
            case .source:
                return L10n.tr("Source")
            case .settings:
                return L10n.tr("Settings")
            case .conversion:
                return L10n.tr("Convert")
            }
        }
    }

    @Published var pickerItem: PhotosPickerItem?

    @Published var targetValueText: String = "25" {
        didSet {
            validateTarget()
            persistCurrentSettingsIfNeeded()
        }
    }

    @Published var targetUnit: CompressionUnit = .mb {
        didSet {
            let normalizedUnit = normalizedTargetUnit(targetUnit)
            if normalizedUnit != targetUnit {
                targetUnit = normalizedUnit
                return
            }
            adjustTargetValueForUnitChange(from: oldValue, to: targetUnit)
            validateTarget()
            persistCurrentSettingsIfNeeded()
        }
    }

    @Published var allowResizeUpTo10x: Bool = false {
        didSet {
            persistCurrentSettingsIfNeeded()
        }
    }

    @Published var selectedResolutionScale: Double = 1.0 {
        didSet {
            persistCurrentSettingsIfNeeded()
        }
    }

    @Published var removeHDR: Bool = false {
        didSet {
            persistCurrentSettingsIfNeeded()
        }
    }

    @Published var selectedOutputFormatID: String = OutputFormatOption.autoID {
        didSet {
            validateTarget()
            persistCurrentSettingsIfNeeded()
        }
    }

    @Published private(set) var sourceMetadata: VideoMetadata?
    @Published private(set) var supportedOutputFormats: [CompressionContainer] = []
    @Published private(set) var sourcePreviewImage: UIImage?
    @Published private(set) var sourceQuickInfoText: String?
    @Published private(set) var convertedVideoURL: URL?
    @Published private(set) var convertedFileSizeBytes: Int64?
    @Published private(set) var statusMessage: String = L10n.tr("Pick a video from your gallery or Files to start.")
    @Published private(set) var validationMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var workflowStep: WorkflowStep = .source
    @Published private(set) var isConverting: Bool = false
    @Published private(set) var isLoadingSourceDetails: Bool = false
    @Published private(set) var isLoadingOutputFormats: Bool = false
    @Published private(set) var didRetryConversion: Bool = false
    @Published private(set) var hasStartedConversion: Bool = false
    @Published private(set) var isCancellingConversion: Bool = false
    @Published private(set) var conversionProgress: Double?
    @Published private(set) var estimatedOutputBytes: Int64?
    @Published private(set) var estimatedPlanReason: String?
    @Published private(set) var purchaseOptions: [PurchasePlanOption] = []
    @Published private(set) var hasPremiumAccess: Bool = false
    @Published private(set) var quotaStatusMessage: String = ""
    @Published private(set) var isPurchasingPlan: Bool = false
    @Published private(set) var isPaywallPresented: Bool = false
    @Published private(set) var isSaveSuccessAlertPresented: Bool = false
    @Published private(set) var saveSuccessMessage: String?

    private let settingsStore = CompressionSettingsStore()
    private let quotaStore = ConversionQuotaStore()
    private let purchaseManager = PurchaseManager()
    private let metadataInspector = VideoMetadataInspector()
    private let compressionService = VideoCompressionService()
    private let planner = CompressionPlanner()

    private var restoringSettings = false
    private var currentLoadRequestID = UUID()
    private var conversionCancellationRequested = false

    init() {
        loadSettings()
        refreshQuotaStatusMessage()
        Task {
            await AppDiagnostics.shared.log(
                category: "app",
                message: "app_start",
                context: .diagnostics(
                    ("bundleID", Bundle.main.bundleIdentifier),
                    ("appVersion", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String),
                    ("build", Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
                )
            )
        }
        if let showcaseStep = launchShowcaseStep() {
            applyShowcaseState(showcaseStep)
        } else {
            validateTarget()
            Task {
                await refreshMonetizationState()
            }
        }
    }

    func returnToSourceStep() {
        guard !isConverting else { return }
        workflowStep = .source
    }

    func returnToSettingsStep() {
        guard !isConverting else { return }
        workflowStep = sourceMetadata == nil ? .source : .settings
    }

    func startNewConversionFlow() {
        guard !isConverting else { return }
        currentLoadRequestID = UUID()
        pickerItem = nil
        sourceMetadata = nil
        supportedOutputFormats = []
        sourcePreviewImage = nil
        sourceQuickInfoText = nil
        convertedVideoURL = nil
        convertedFileSizeBytes = nil
        errorMessage = nil
        validationMessage = nil
        statusMessage = L10n.tr("Pick a video from your gallery or Files to start.")
        isLoadingSourceDetails = false
        isLoadingOutputFormats = false
        didRetryConversion = false
        hasStartedConversion = false
        isCancellingConversion = false
        conversionProgress = nil
        isPaywallPresented = false
        isSaveSuccessAlertPresented = false
        saveSuccessMessage = nil
        estimatedOutputBytes = nil
        estimatedPlanReason = nil
        refreshQuotaStatusMessage()
        workflowStep = .source
    }

    var formatOptions: [OutputFormatOption] {
        var options: [OutputFormatOption] = [OutputFormatOption(id: OutputFormatOption.autoID, title: L10n.tr("Auto"))]
        var containers = metadataInspector.allWriterOutputFormats()
        for container in supportedOutputFormats where !containers.contains(container) {
            containers.append(container)
        }

        for container in containers {
            let isUnavailableForCurrentSource = sourceMetadata != nil && !supportedOutputFormats.contains(container)
            let title = isUnavailableForCurrentSource
                ? L10n.fmt("%@ (unavailable for this video)", container.label)
                : container.label
            let option = OutputFormatOption(id: container.identifier, title: title)
            options.append(option)
        }
        return options
    }

    var availableTargetUnits: [CompressionUnit] {
        guard let sourceMetadata else {
            return [.kb, .mb]
        }

        if sourceMetadata.fileSizeBytes < Int64(CompressionUnit.mb.multiplier) {
            return [.kb]
        }

        return [.kb, .mb]
    }

    var resolutionOptions: [ResolutionOption] {
        guard let sourceMetadata else {
            return [ResolutionOption(id: "source", title: L10n.tr("Same as source"), scale: 1.0)]
        }
        return buildResolutionOptions(from: sourceMetadata)
    }

    var sourceSummaryText: String? {
        guard let sourceMetadata else { return nil }
        let durationText = String(format: "%.1f s", sourceMetadata.durationSeconds)
        let hdrText = sourceMetadata.hasHDR ? L10n.tr("HDR") : L10n.tr("SDR")
        return "\(sourceMetadata.width)x\(sourceMetadata.height), \(durationText), \(sourceMetadata.codec.rawValue.uppercased()), \(hdrText), \(sourceMetadata.container.label)"
    }

    var sourceSizeText: String? {
        guard let sourceMetadata else { return nil }
        return humanReadableSize(sourceMetadata.fileSizeBytes)
    }

    var outputSizeText: String? {
        guard let convertedFileSizeBytes else { return nil }
        return humanReadableSize(convertedFileSizeBytes)
    }

    var estimatedOutputText: String? {
        guard let estimatedOutputBytes else { return nil }
        return humanReadableSize(estimatedOutputBytes)
    }

    var targetSizeText: String? {
        guard let settings = try? currentSettings() else { return nil }
        let bytes = planner.bytes(for: settings.targetValue, unit: settings.targetUnit)
        return humanReadableSize(bytes)
    }

    var canUseFreeConversionToday: Bool {
        quotaStore.canUseFreeConversionToday()
    }

    var canStartConversionToday: Bool {
        hasPremiumAccess || canUseFreeConversionToday
    }

    var canConvert: Bool {
        sourceMetadata != nil
            && !isConverting
            && !isLoadingSourceDetails
            && !isLoadingOutputFormats
            && validationMessage == nil
            && canStartConversionToday
    }

    var canSaveResult: Bool {
        convertedVideoURL != nil && !isConverting
    }

    var canCancelConversion: Bool {
        isConverting && !isCancellingConversion
    }

    var hasConversionSucceeded: Bool {
        !isConverting && convertedVideoURL != nil && errorMessage == nil
    }

    var hasConversionFailed: Bool {
        hasStartedConversion && !isConverting && convertedVideoURL == nil && errorMessage != nil
    }

    var conversionProgressPercentText: String? {
        guard let conversionProgress else { return nil }
        return "\(Int((conversionProgress * 100).rounded()))%"
    }

    var sliderRange: ClosedRange<Double> {
        sliderRange(for: targetUnit)
    }

    var sliderStep: Double {
        defaultSliderStep(for: targetUnit)
    }

    var targetSliderValue: Double {
        get {
            let value = parsedTargetValue() ?? sliderRange.lowerBound
            let snapped = value.rounded()
            return clamp(snapped, to: sliderRange)
        }
        set {
            let clampedValue = clamp(newValue, to: sliderRange)
            let snapped = clampedValue.rounded()
            targetValueText = String(Int(snapped))
        }
    }

    var sliderMinLabel: String {
        String(Int(sliderRange.lowerBound.rounded()))
    }

    var sliderMaxLabel: String {
        String(Int(sliderRange.upperBound.rounded()))
    }

    func handlePickerChange() async {
        guard let pickerItem else {
            return
        }

        let requestID = UUID()
        prepareForSourceLoading(
            requestID: requestID,
            initialStatus: L10n.tr("Loading selected video...")
        )

        do {
            let sourceURL = try await resolveSourceURL(from: pickerItem, requestID: requestID)
            guard requestID == currentLoadRequestID else { return }
            let stagedURL = (try? stageResolvedSourceForProcessing(from: sourceURL)) ?? sourceURL
            guard requestID == currentLoadRequestID else { return }
            try await processSelectedSource(url: stagedURL, requestID: requestID)
        } catch {
            completeSourceLoadingWithFailure(
                requestID: requestID,
                status: L10n.tr("Failed to load selected video."),
                error: error
            )
        }
    }

    func importFromFiles(url: URL) async {
        let requestID = UUID()
        prepareForSourceLoading(
            requestID: requestID,
            initialStatus: L10n.tr("Importing video from Files...")
        )

        do {
            let importedURL = try stageImportedFileForProcessing(from: url)
            guard requestID == currentLoadRequestID else { return }
            sourceQuickInfoText = quickInfoText(for: importedURL)
            try await processSelectedSource(url: importedURL, requestID: requestID)
        } catch {
            completeSourceLoadingWithFailure(
                requestID: requestID,
                status: L10n.tr("Failed to import selected file."),
                error: error
            )
        }
    }

    func handleFileImportFailure(_ error: Error) {
        let nsError = error as NSError
        if nsError.code == NSUserCancelledError {
            return
        }

        statusMessage = L10n.tr("Failed to import selected file.")
        errorMessage = error.localizedDescription
    }

    func presentPaywall() {
        isPaywallPresented = true
        Task {
            await refreshMonetizationState()
        }
    }

    func dismissPaywall() {
        isPaywallPresented = false
    }

    func purchasePlan(planID: String) async {
        guard !isPurchasingPlan else { return }

        isPurchasingPlan = true
        errorMessage = nil

        do {
            let didPurchase = try await purchaseManager.purchase(productID: planID)
            if didPurchase {
                hasPremiumAccess = await purchaseManager.hasActiveEntitlement()
                if hasPremiumAccess {
                    statusMessage = L10n.tr("Premium unlocked. Unlimited conversions enabled.")
                    isPaywallPresented = false
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isPurchasingPlan = false
        await refreshMonetizationState()
    }

    func restorePurchases() async {
        guard !isPurchasingPlan else { return }

        isPurchasingPlan = true
        errorMessage = nil

        do {
            let hasRestoredAccess = try await purchaseManager.restorePurchases()
            if hasRestoredAccess {
                statusMessage = L10n.tr("Purchases restored. Unlimited conversions enabled.")
                isPaywallPresented = false
            } else {
                statusMessage = L10n.tr("No active purchases found.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isPurchasingPlan = false
        await refreshMonetizationState()
    }

    private func prepareForSourceLoading(requestID: UUID, initialStatus: String) {
        workflowStep = .settings
        currentLoadRequestID = requestID
        errorMessage = nil
        sourceMetadata = nil
        supportedOutputFormats = []
        sourcePreviewImage = nil
        sourceQuickInfoText = nil
        convertedVideoURL = nil
        convertedFileSizeBytes = nil
        didRetryConversion = false
        hasStartedConversion = false
        isCancellingConversion = false
        conversionProgress = nil
        isLoadingSourceDetails = true
        isLoadingOutputFormats = false
        statusMessage = initialStatus
    }

    private func completeSourceLoadingWithFailure(requestID: UUID, status: String, error: Error) {
        guard requestID == currentLoadRequestID else {
            return
        }
        sourceMetadata = nil
        supportedOutputFormats = []
        sourcePreviewImage = nil
        sourceQuickInfoText = nil
        isLoadingSourceDetails = false
        isLoadingOutputFormats = false
        statusMessage = status
        errorMessage = sourceLoadErrorMessage(from: error)
        workflowStep = .source
        refreshEstimatedPlan()
    }

    private func processSelectedSource(url sourceURL: URL, requestID: UUID) async throws {
        async let inspectedMetadata = metadataInspector.inspect(url: sourceURL)

        if sourcePreviewImage == nil {
            statusMessage = L10n.tr("Loading first frame preview...")
            sourcePreviewImage = await metadataInspector.generateFirstFramePreview(
                from: sourceURL,
                maxDimension: 420
            )
        }
        guard requestID == currentLoadRequestID else {
            return
        }
        statusMessage = L10n.tr("Preview ready. Loading video details...")

        let metadata = try await inspectedMetadata
        guard requestID == currentLoadRequestID else {
            return
        }

        sourceMetadata = metadata
        if !resolutionOptions.contains(where: { abs($0.scale - selectedResolutionScale) < 0.0001 }) {
            selectedResolutionScale = 1.0
        }
        let suggestion = suggestedTarget(fromSourceBytes: metadata.fileSizeBytes)
        targetUnit = suggestion.unit
        targetValueText = trimNumber(suggestion.value)
        validateTarget()
        isLoadingSourceDetails = false
        isLoadingOutputFormats = true
        statusMessage = L10n.fmt(
            "Video loaded. Suggested target: %@ %@ (~2x smaller).",
            trimNumber(suggestion.value),
            suggestion.unit.label
        )

        Task {
            let supportedFormats = await metadataInspector.supportedOutputFormats(for: sourceURL, metadata: metadata)
            await MainActor.run {
                guard requestID == self.currentLoadRequestID else {
                    return
                }
                self.supportedOutputFormats = supportedFormats
                if self.selectedOutputFormatID != OutputFormatOption.autoID,
                   !supportedFormats.contains(CompressionContainer(identifier: self.selectedOutputFormatID))
                {
                    self.selectedOutputFormatID = OutputFormatOption.autoID
                }
                self.isLoadingOutputFormats = false
                self.validateTarget()
            }
        }
    }

    private func resolveSourceURL(from pickerItem: PhotosPickerItem, requestID: UUID) async throws -> URL {
        if !isVideoPickerSelection(pickerItem) {
            throw SourceLoadError.unsupportedSelection
        }

        let photoLibraryStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let canUsePhotoKitFastPath = photoLibraryStatus == .authorized

        if canUsePhotoKitFastPath,
           let itemIdentifier = pickerItem.itemIdentifier,
           let asset = metadataInspector.fetchAsset(localIdentifier: itemIdentifier)
        {
            sourceQuickInfoText = quickInfoText(for: asset)

            async let previewImageFromAsset = metadataInspector.generatePreviewImage(from: asset, maxDimension: 420)
            async let playableURL = metadataInspector.requestPlayableURL(for: asset)

            sourcePreviewImage = await previewImageFromAsset
            guard requestID == currentLoadRequestID else {
                throw CancellationError()
            }

            if let url = await playableURL {
                return url
            }
        }

        let pickedVideo: PickedVideo
        do {
            guard let resolved = try await pickerItem.loadTransferable(type: PickedVideo.self) else {
                throw SourceLoadError.noVideoSelected
            }
            pickedVideo = resolved
        } catch {
            let nsError = error as NSError
            if nsError.domain == "CoreTransferable.TransferableSupportError" {
                throw SourceLoadError.unsupportedSelection
            }
            throw error
        }

        if sourceQuickInfoText == nil {
            sourceQuickInfoText = quickInfoText(for: pickedVideo.url)
        }

        if sourcePreviewImage == nil {
            sourcePreviewImage = await metadataInspector.generateFirstFramePreview(
                from: pickedVideo.url,
                maxDimension: 420
            )
        }

        return pickedVideo.url
    }

    private func isVideoPickerSelection(_ pickerItem: PhotosPickerItem) -> Bool {
        let types = pickerItem.supportedContentTypes
        guard !types.isEmpty else {
            return true
        }
        return types.contains { type in
            type.conforms(to: .movie) || type.conforms(to: .video)
        }
    }

    private func sourceLoadErrorMessage(from error: Error) -> String {
        if let sourceLoadError = error as? SourceLoadError,
           let errorDescription = sourceLoadError.errorDescription
        {
            return errorDescription
        }

        let nsError = error as NSError
        if nsError.domain == "CoreTransferable.TransferableSupportError" {
            return L10n.tr("Please select a video from Gallery.")
        }

        return error.localizedDescription
    }

    private func stageImportedFileForProcessing(from originalURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let outputExtension = originalURL.pathExtension.isEmpty ? "mov" : originalURL.pathExtension
        let localURL = fileManager.temporaryDirectory
            .appendingPathComponent("files-import-\(UUID().uuidString)")
            .appendingPathExtension(outputExtension)

        let canAccessSecureScope = originalURL.startAccessingSecurityScopedResource()
        defer {
            if canAccessSecureScope {
                originalURL.stopAccessingSecurityScopedResource()
            }
        }

        try fileManager.copyItem(at: originalURL, to: localURL)
        return localURL
    }

    private func stageResolvedSourceForProcessing(from originalURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let outputExtension = originalURL.pathExtension.isEmpty ? "mov" : originalURL.pathExtension
        let localURL = fileManager.temporaryDirectory
            .appendingPathComponent("gallery-import-\(UUID().uuidString)")
            .appendingPathExtension(outputExtension)

        if fileManager.fileExists(atPath: localURL.path) {
            try fileManager.removeItem(at: localURL)
        }

        try fileManager.copyItem(at: originalURL, to: localURL)
        return localURL
    }

    func convert() async {
        guard !isConverting else { return }
        guard let sourceMetadata else {
            validationMessage = L10n.tr("Select a source video first.")
            workflowStep = .source
            return
        }

        errorMessage = nil
        convertedVideoURL = nil
        convertedFileSizeBytes = nil
        didRetryConversion = false

        let settings: CompressionSettings
        do {
            settings = try currentSettings()
        } catch {
            validationMessage = error.localizedDescription
            return
        }

        validateTarget()
        guard validationMessage == nil else {
            workflowStep = .settings
            return
        }

        guard canStartConversionToday else {
            statusMessage = L10n.tr("Daily free limit reached.")
            errorMessage = L10n.tr("Free plan allows only 1 conversion per day. Upgrade for unlimited conversions.")
            isPaywallPresented = true
            return
        }

        workflowStep = .conversion
        hasStartedConversion = true
        isConverting = true
        conversionCancellationRequested = false
        isCancellingConversion = false
        conversionProgress = 0
        statusMessage = L10n.tr("Starting first conversion pass...")
        settingsStore.save(settings)
        Task {
            await AppDiagnostics.shared.log(
                category: "conversion",
                message: "conversion_started",
                context: .diagnostics(
                    ("sourceSizeBytes", "\(sourceMetadata.fileSizeBytes)"),
                    ("durationSeconds", String(format: "%.3f", sourceMetadata.durationSeconds)),
                    ("dimensions", "\(sourceMetadata.width)x\(sourceMetadata.height)"),
                    ("fps", String(format: "%.2f", sourceMetadata.frameRate)),
                    ("codec", sourceMetadata.codec.rawValue),
                    ("container", sourceMetadata.container.identifier),
                    ("targetValue", settings.targetValue.description),
                    ("targetUnit", settings.targetUnit.rawValue),
                    ("targetBytes", "\(planner.bytes(for: settings.targetValue, unit: settings.targetUnit))"),
                    ("allowResize", "\(settings.allowResizeUpTo10x)"),
                    ("removeHDR", "\(settings.removeHDR)"),
                    ("formatOverride", settings.outputFormatIdentifier)
                )
            )
        }

        var shouldReturnToSourceAfterCancellation = false

        do {
            try throwIfCancellationRequested()
            let outputURL = try await compressToTargetSize(
                sourceMetadata: sourceMetadata,
                settings: settings
            )
            try throwIfCancellationRequested()
            try await ensureAudioPreservedIfRequired(
                sourceMetadata: sourceMetadata,
                outputURL: outputURL
            )
            try throwIfCancellationRequested()
            try finalizeSuccessfulConversion(
                outputURL: outputURL,
                sourceMetadata: sourceMetadata
            )
        } catch {
            if isCancellationError(error) {
                shouldReturnToSourceAfterCancellation = true
                statusMessage = L10n.tr("Conversion cancelled.")
                errorMessage = nil
                conversionProgress = nil
                convertedVideoURL = nil
                convertedFileSizeBytes = nil
                Task {
                    await AppDiagnostics.shared.log(
                        level: "warn",
                        category: "conversion",
                        message: "conversion_cancelled",
                        context: .diagnostics(
                            ("error", error.localizedDescription)
                        )
                    )
                }
            } else {
                statusMessage = L10n.tr("Conversion failed.")
                errorMessage = friendlyConversionErrorMessage(from: error)
                conversionProgress = nil
                convertedVideoURL = nil
                convertedFileSizeBytes = nil
                let nsError = error as NSError
                Task {
                    await AppDiagnostics.shared.log(
                        level: "error",
                        category: "conversion",
                        message: "conversion_failed",
                        context: .diagnostics(
                            ("error", error.localizedDescription),
                            ("errorDomain", nsError.domain),
                            ("errorCode", "\(nsError.code)")
                        )
                    )
                }
            }
        }

        refreshQuotaStatusMessage()
        conversionCancellationRequested = false
        isCancellingConversion = false
        isConverting = false

        if shouldReturnToSourceAfterCancellation {
            startNewConversionFlow()
        }
    }

    private func ensureAudioPreservedIfRequired(
        sourceMetadata: VideoMetadata,
        outputURL: URL
    ) async throws {
        guard sourceMetadata.sourceAudioBitrate > 0 else {
            return
        }

        let outputMetadata = try await metadataInspector.inspect(url: outputURL)
        guard outputMetadata.sourceAudioBitrate > 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            Task {
                await AppDiagnostics.shared.log(
                    level: "error",
                    category: "conversion",
                    message: "conversion_rejected_missing_audio_track",
                    context: .diagnostics(
                        ("sourceURL", sourceMetadata.sourceURL.lastPathComponent),
                        ("outputURL", outputURL.lastPathComponent)
                    )
                )
            }
            throw ConversionTargetError.audioTrackMissingInOutput
        }
    }

    func cancelConversion() {
        guard isConverting else { return }
        guard !isCancellingConversion else { return }

        conversionCancellationRequested = true
        isCancellingConversion = true
        statusMessage = L10n.tr("Cancelling conversion...")
        compressionService.cancelCurrentCompression()
    }

    func saveToPhotoLibrary() async {
        guard let convertedVideoURL else { return }

        errorMessage = nil
        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            errorMessage = L10n.tr("Photo Library access is required to save the converted video.")
            return
        }

        let fileManager = FileManager.default
        let outputExtension = convertedVideoURL.pathExtension.isEmpty ? "mp4" : convertedVideoURL.pathExtension
        let importURL = fileManager.temporaryDirectory
            .appendingPathComponent("photo-export-\(UUID().uuidString)")
            .appendingPathExtension(outputExtension)

        do {
            if fileManager.fileExists(atPath: importURL.path) {
                try fileManager.removeItem(at: importURL)
            }
            try fileManager.copyItem(at: convertedVideoURL, to: importURL)

            try await PHPhotoLibrary.shared().performChanges {
                if let request = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: importURL) {
                    // Force a fresh item in Recents instead of inheriting an old capture timestamp.
                    request.creationDate = Date()
                }
            }
            try? fileManager.removeItem(at: importURL)
            statusMessage = L10n.tr("Saved to Photo Library.")
            saveSuccessMessage = L10n.tr("Video saved to Photo Library.")
            isSaveSuccessAlertPresented = true
        } catch {
            try? fileManager.removeItem(at: importURL)
            errorMessage = L10n.fmt("Failed to save to Photo Library: %@", error.localizedDescription)
            let nsError = error as NSError
            Task {
                await AppDiagnostics.shared.log(
                    level: "error",
                    category: "save",
                    message: "save_photo_library_failed",
                    context: .diagnostics(
                        ("error", error.localizedDescription),
                        ("errorDomain", nsError.domain),
                        ("errorCode", "\(nsError.code)")
                    )
                )
            }
        }
    }

    func didSaveToFiles() {
        errorMessage = nil
        statusMessage = L10n.tr("Saved to Files.")
        saveSuccessMessage = L10n.tr("Video saved to Files.")
        isSaveSuccessAlertPresented = true
    }

    func handleSaveToFilesFailure(_ error: Error) {
        errorMessage = L10n.fmt("Failed to save to Files: %@", error.localizedDescription)
    }

    func dismissSaveSuccessAlert() {
        isSaveSuccessAlertPresented = false
        saveSuccessMessage = nil
    }

#if DEBUG
    func debugResetLimitsForTesting() {
        quotaStore.debugResetFreeConversionsToday()
        errorMessage = nil
        refreshQuotaStatusMessage()
        statusMessage = L10n.tr("Debug: free conversion limit reset for today.")
    }
#endif

    func validateTarget() {
        defer { refreshEstimatedPlan() }

        guard let settings = try? currentSettings() else {
            validationMessage = L10n.tr("Enter a valid positive target size.")
            return
        }

        guard let sourceMetadata else {
            validationMessage = nil
            return
        }

        if let outputIdentifier = settings.outputFormatIdentifier,
           !supportedOutputFormats.contains(CompressionContainer(identifier: outputIdentifier))
        {
            validationMessage = L10n.tr("Selected format is not available for this source video.")
            return
        }

        let targetBytes = planner.bytes(for: settings.targetValue, unit: settings.targetUnit)
        let minimumBytes = Int64((Double(sourceMetadata.fileSizeBytes) / CompressionPlanner.maxCompressionRatio).rounded(.up))

        if targetBytes > sourceMetadata.fileSizeBytes {
            validationMessage = L10n.fmt(
                "Target size cannot be larger than source size (%@).",
                humanReadableSize(sourceMetadata.fileSizeBytes)
            )
            return
        }

        if targetBytes < minimumBytes {
            validationMessage = L10n.fmt(
                "Target is too small. Max compression is 30x (minimum %@).",
                humanReadableSize(minimumBytes)
            )
        } else {
            validationMessage = nil
        }
    }

    private func currentSettings() throws -> CompressionSettings {
        guard let value = Double(targetValueText.replacingOccurrences(of: ",", with: ".")), value > 0 else {
            throw CompressionPlannerError.invalidTargetValue
        }

        return CompressionSettings(
            targetValue: value,
            targetUnit: targetUnit,
            allowResizeUpTo10x: allowResizeUpTo10x,
            removeHDR: removeHDR,
            outputFormatIdentifier: selectedOutputFormatID == OutputFormatOption.autoID ? nil : selectedOutputFormatID,
            preferredResizeScale: allowResizeUpTo10x ? selectedResolutionScale : nil
        )
    }

    private func loadSettings() {
        restoringSettings = true
        defer { restoringSettings = false }

        guard let settings = settingsStore.load() else {
            return
        }

        targetValueText = trimNumber(settings.targetValue)
        targetUnit = settings.targetUnit
        allowResizeUpTo10x = settings.allowResizeUpTo10x
        selectedResolutionScale = settings.preferredResizeScale ?? 1.0
        removeHDR = settings.removeHDR
        selectedOutputFormatID = settings.outputFormatIdentifier ?? OutputFormatOption.autoID
    }

    private func persistCurrentSettingsIfNeeded() {
        guard !restoringSettings else { return }
        guard let settings = try? currentSettings() else { return }
        settingsStore.save(settings)
    }

    private func trimNumber(_ value: Double) -> String {
        if value.rounded() == value {
            String(Int(value))
        } else {
            String(value)
        }
    }

    private func parsedTargetValue() -> Double? {
        guard let value = Double(targetValueText.replacingOccurrences(of: ",", with: ".")), value > 0 else {
            return nil
        }
        return value
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func sliderRange(for unit: CompressionUnit) -> ClosedRange<Double> {
        let minimumForUnit = defaultSliderMinimum(for: unit)
        let maximumForUnit = defaultSliderMaximum(for: unit)

        guard let sourceMetadata else {
            return minimumForUnit...maximumForUnit
        }

        let minimumBytes = Int64(
            (Double(sourceMetadata.fileSizeBytes) / CompressionPlanner.maxCompressionRatio).rounded(.up)
        )
        let sourceValueInUnit = Double(sourceMetadata.fileSizeBytes) / unit.multiplier
        let minimumValueRaw = max(minimumForUnit, Double(minimumBytes) / unit.multiplier)
        let maximumValueRaw = min(maximumForUnit, sourceValueInUnit)

        let minimumValue = Double(Int(ceil(minimumValueRaw)))
        let maximumValue = Double(Int(floor(maximumValueRaw)))

        if maximumValue < minimumValue {
            return minimumValue...minimumValue
        }
        return minimumValue...maximumValue
    }

    private func adjustTargetValueForUnitChange(from oldUnit: CompressionUnit, to newUnit: CompressionUnit) {
        guard oldUnit != newUnit else { return }

        let previousValue = parsedTargetValue() ?? sliderRange(for: oldUnit).lowerBound
        let previousBytes = planner.bytes(for: previousValue, unit: oldUnit)
        let convertedValue = Double(previousBytes) / newUnit.multiplier

        let range = sliderRange(for: newUnit)
        let adjustedValue = clamp(convertedValue.rounded(), to: range)
        targetValueText = String(Int(adjustedValue))
    }

    private func defaultSliderMinimum(for unit: CompressionUnit) -> Double {
        switch unit {
        case .kb:
            return 1
        case .mb:
            return 1
        case .gb:
            return 1
        }
    }

    private func defaultSliderMaximum(for unit: CompressionUnit) -> Double {
        switch unit {
        case .kb:
            return 102_400
        case .mb:
            return 10_240
        case .gb:
            return 20
        }
    }

    private func defaultSliderStep(for unit: CompressionUnit) -> Double {
        switch unit {
        case .kb:
            return 1
        case .mb:
            return 1
        case .gb:
            return 1
        }
    }

    private func normalizedTargetUnit(_ unit: CompressionUnit) -> CompressionUnit {
        if availableTargetUnits.contains(unit) {
            return unit
        }
        return preferredTargetUnit()
    }

    private func preferredTargetUnit() -> CompressionUnit {
        if availableTargetUnits.contains(.mb) {
            return .mb
        }
        return .kb
    }

    private func quickInfoText(for url: URL) -> String {
        let fileExtension = url.pathExtension.uppercased()
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .fileAllocatedSizeKey])
        let bytes = Int64(resourceValues?.fileSize ?? resourceValues?.fileAllocatedSize ?? 0)
        if bytes > 0 {
            return L10n.fmt("Detected: %@ • %@", fileExtension, humanReadableSize(bytes))
        }
        return L10n.fmt("Detected: %@", fileExtension)
    }

    private func quickInfoText(for asset: PHAsset) -> String {
        let durationText = String(format: "%.1f s", asset.duration)
        let dimensions = "\(asset.pixelWidth)x\(asset.pixelHeight)"
        return L10n.fmt("Detected: %@ • %@", dimensions, durationText)
    }

    private func finalizeSuccessfulConversion(outputURL: URL, sourceMetadata: VideoMetadata) throws {
        let outputSize = try fileSize(for: outputURL)
        guard outputSize > 0 else {
            throw VideoCompressionServiceError.noFinalOutput
        }

        convertedVideoURL = outputURL
        convertedFileSizeBytes = outputSize
        errorMessage = nil

        if !hasPremiumAccess {
            quotaStore.recordFreeConversionToday()
            refreshQuotaStatusMessage()
        }

        if let convertedFileSizeBytes {
            statusMessage = L10n.fmt(
                "Done. Output size: %@ (source: %@).",
                humanReadableSize(convertedFileSizeBytes),
                humanReadableSize(sourceMetadata.fileSizeBytes)
            )
        } else {
            statusMessage = L10n.tr("Done.")
        }

        conversionProgress = 1
        Task {
            await AppDiagnostics.shared.log(
                category: "conversion",
                message: "conversion_succeeded",
                context: .diagnostics(
                    ("sourceSizeBytes", "\(sourceMetadata.fileSizeBytes)"),
                    ("outputSizeBytes", convertedFileSizeBytes.map { "\($0)" }),
                    ("statusMessage", statusMessage),
                    ("outputURL", outputURL.lastPathComponent)
                )
            )
        }
    }

    private func friendlyConversionErrorMessage(from error: Error) -> String {
        if let targetError = error as? ConversionTargetError,
           let description = targetError.errorDescription
        {
            return description
        }

        let lowered = error.localizedDescription.lowercased()
        if lowered.contains("cannot encode") || lowered.contains("encode media") {
            return L10n.tr("Cannot encode this video with current settings. Try MP4 format and disable HDR, then convert again.")
        }
        return error.localizedDescription
    }

    private func compressToTargetSize(
        sourceMetadata: VideoMetadata,
        settings: CompressionSettings
    ) async throws -> URL {
        let supportedFormats = supportedOutputFormats.isEmpty
            ? CompressionContainer.preferredAutoOrder
            : supportedOutputFormats
        var currentPlan = try planner.makePlan(
            source: sourceMetadata.sourceProfile,
            settings: settings,
            supportedOutputFormats: supportedFormats
        )
        let targetBytes = currentPlan.targetBytes
        var bestOversizedBytes: Int64 = .max
        let primaryAttempts = 5
        let primaryPhaseWeight = 0.72
        let primaryAttemptWeight = primaryPhaseWeight / Double(primaryAttempts)

        for attempt in 1...primaryAttempts {
            try throwIfCancellationRequested()
            statusMessage = attempt == 1
                ? L10n.tr("Starting first conversion pass...")
                : L10n.fmt("Optimizing to match target... (%d/%d)", attempt, primaryAttempts)
            if attempt > 1 {
                didRetryConversion = true
                conversionProgress = max(conversionProgress ?? 0, Double(attempt - 1) * primaryAttemptWeight)
            }

            do {
                let outputURL = try await compressionService.compress(
                    sourceURL: sourceMetadata.sourceURL,
                    metadata: sourceMetadata,
                    plan: currentPlan,
                    removeHDR: settings.removeHDR,
                    progressHandler: { [weak self] progress in
                        Task { @MainActor in
                            let normalized = min(max(progress, 0), 1)
                            let mapped = min(
                                primaryPhaseWeight,
                                (Double(attempt - 1) * primaryAttemptWeight) + (normalized * primaryAttemptWeight)
                            )
                            self?.conversionProgress = max(self?.conversionProgress ?? 0, mapped)
                        }
                    }
                )
                let outputSize = try fileSize(for: outputURL)

                if outputSize <= targetBytes {
                    return outputURL
                }

                bestOversizedBytes = min(bestOversizedBytes, outputSize)
                try? FileManager.default.removeItem(at: outputURL)

                statusMessage = L10n.fmt(
                    "Output %@ is above target %@. Retrying with stronger compression...",
                    humanReadableSize(outputSize),
                    humanReadableSize(targetBytes)
                )
                currentPlan = makeStricterPlan(
                    priorPlan: currentPlan,
                    sourceMetadata: sourceMetadata,
                    settings: settings,
                    supportedOutputFormats: supportedFormats
                )
            } catch {
                if isCancellationError(error) {
                    throw error
                }
                if !shouldTryCompatibilityFallback(for: error) {
                    throw error
                }
                break
            }
        }

        return try await compressWithGuaranteedFallback(
            sourceMetadata: sourceMetadata,
            targetBytes: targetBytes,
            bestOversizedBytes: bestOversizedBytes
        )
    }

    private func makeStricterPlan(
        priorPlan: CompressionPlan,
        sourceMetadata: VideoMetadata,
        settings: CompressionSettings,
        supportedOutputFormats: [CompressionContainer]
    ) -> CompressionPlan {
        var retryPlan = (try? planner.makeRetryPlan(
            source: sourceMetadata.sourceProfile,
            priorPlan: priorPlan,
            settings: settings,
            supportedOutputFormats: supportedOutputFormats
        )) ?? priorPlan

        let didGetStrictEnoughPlan =
            retryPlan.targetVideoBitrate < priorPlan.targetVideoBitrate ||
                retryPlan.targetAudioBitrate < priorPlan.targetAudioBitrate ||
                retryPlan.resizeScale < priorPlan.resizeScale

        if !didGetStrictEnoughPlan {
            retryPlan.targetVideoBitrate = max(70_000, Int(Double(priorPlan.targetVideoBitrate) * 0.82))
            retryPlan.targetAudioBitrate = max(16_000, Int(Double(priorPlan.targetAudioBitrate) * 0.78))
            let minScale = 0.25
            retryPlan.resizeScale = max(minScale, min(priorPlan.resizeScale, priorPlan.resizeScale * 0.9))
            retryPlan.reason = "Forced stricter retry"
        }

        return retryPlan
    }

    private func shouldTryCompatibilityFallback(for error: Error) -> Bool {
        if isCancellationError(error) {
            return false
        }

        if let compressionError = error as? VideoCompressionServiceError {
            switch compressionError {
            case .cannotCreateReader,
                 .cannotCreateWriter,
                 .cannotAddVideoOutput,
                 .cannotAddVideoInput,
                 .cannotAddAudioOutput,
                 .cannotAddAudioInput,
                 .startReadingFailed,
                 .startWritingFailed,
                 .appendFailed,
                 .noFinalOutput,
                 .exportSessionUnavailable,
                 .exportFailed:
                return true
            case .cancelled:
                return false
            default:
                break
            }
        }

        let lowered = error.localizedDescription.lowercased()
        if lowered.contains("cannot encode") ||
            lowered.contains("encode media") ||
            lowered.contains("operation could not be completed")
        {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == AVFoundationErrorDomain {
            if nsError.code == -11800 || nsError.code == -11861 || nsError.code == -11821 {
                return true
            }
            return lowered.contains("encode") || lowered.contains("encoder")
        }

        return false
    }

    private func throwIfCancellationRequested() throws {
        if conversionCancellationRequested || Task.isCancelled {
            throw VideoCompressionServiceError.cancelled
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if case VideoCompressionServiceError.cancelled = error {
            return true
        }
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }

    private func compressWithGuaranteedFallback(
        sourceMetadata: VideoMetadata,
        targetBytes: Int64,
        bestOversizedBytes: Int64
    ) async throws -> URL {
        statusMessage = L10n.tr("Applying aggressive compatibility mode...")
        didRetryConversion = true
        let fallbackPhaseStart = 0.72
        let fallbackPhaseWeight = 0.23
        conversionProgress = max(conversionProgress ?? 0, fallbackPhaseStart)

        let duration = max(sourceMetadata.durationSeconds, 0.001)
        let totalBitrateBudget = max(96_000, Int((Double(targetBytes) * 8 / duration) * 0.985))
        let sourceHasAudio = sourceMetadata.sourceAudioBitrate > 0
        let lowTargetMode = totalBitrateBudget < 180_000 || duration < 30
        let fallbackMinScale = 0.25
        let audioFloor = lowTargetMode ? 12_000 : 16_000
        let videoFloor = lowTargetMode ? 110_000 : 85_000
        var resizeScale = 0.92
        var targetAudioBitrate: Int
        if sourceHasAudio {
            let preferredAudio = min(max(24_000, sourceMetadata.sourceAudioBitrate), 80_000)
            let budgetLimitedAudio = max(16_000, totalBitrateBudget / 3)
            targetAudioBitrate = min(preferredAudio, budgetLimitedAudio)
            if lowTargetMode {
                targetAudioBitrate = min(targetAudioBitrate, max(audioFloor, totalBitrateBudget / 5))
            }
        } else {
            targetAudioBitrate = 0
        }
        var targetVideoBitrate = max(videoFloor, totalBitrateBudget - targetAudioBitrate)
        var bestSeenBytes = bestOversizedBytes
        var lastCompressionError: Error?
        let maxAttempts = 12
        let attemptWeight = fallbackPhaseWeight / Double(maxAttempts)
        let outputContainers: [CompressionContainer] = [.mp4, .mov, .m4v]

        for attempt in 1...maxAttempts {
            try throwIfCancellationRequested()
            statusMessage = L10n.fmt("Compatibility retry... (%d/%d)", attempt, maxAttempts)
            conversionProgress = max(
                conversionProgress ?? 0,
                fallbackPhaseStart + (Double(attempt - 1) * attemptWeight)
            )
            let attemptVideoBitrate = targetVideoBitrate
            let attemptAudioBitrate = targetAudioBitrate
            let attemptResizeScale = resizeScale
            Task {
                await AppDiagnostics.shared.log(
                    level: "warn",
                    category: "conversion",
                    message: "compatibility_retry_attempt",
                    context: .diagnostics(
                        ("attempt", "\(attempt)"),
                        ("maxAttempts", "\(maxAttempts)"),
                        ("targetBytes", "\(targetBytes)"),
                        ("videoBitrate", "\(attemptVideoBitrate)"),
                        ("audioBitrate", "\(attemptAudioBitrate)"),
                        ("resizeScale", String(format: "%.4f", attemptResizeScale))
                    )
                )
            }

            let outputContainer = outputContainers[(attempt - 1) % outputContainers.count]
            let fallbackPlan = CompressionPlan(
                targetBytes: targetBytes,
                outputContainer: outputContainer,
                outputCodec: .h264,
                targetVideoBitrate: targetVideoBitrate,
                targetAudioBitrate: targetAudioBitrate,
                resizeScale: resizeScale,
                estimatedOutputBytes: targetBytes,
                reason: "Guaranteed fallback"
            )

            do {
                let outputURL = try await compressionService.compress(
                    sourceURL: sourceMetadata.sourceURL,
                    metadata: sourceMetadata,
                    plan: fallbackPlan,
                    removeHDR: true,
                    progressHandler: { [weak self] progress in
                        Task { @MainActor in
                            let normalized = min(max(progress, 0), 1)
                            let mapped = fallbackPhaseStart + (Double(attempt - 1) * attemptWeight) + (normalized * attemptWeight)
                            self?.conversionProgress = max(self?.conversionProgress ?? 0, mapped)
                        }
                    }
                )

                let outputSize = try fileSize(for: outputURL)
                if outputSize <= targetBytes {
                    return outputURL
                }

                bestSeenBytes = min(bestSeenBytes, outputSize)
                try? FileManager.default.removeItem(at: outputURL)

                // Tighten slowly to avoid AVFoundation encoder failures on low-bitrate passes.
                targetVideoBitrate = max(videoFloor, Int(Double(targetVideoBitrate) * 0.90))
                if sourceHasAudio {
                    targetAudioBitrate = max(audioFloor, Int(Double(targetAudioBitrate) * 0.88))
                }
                resizeScale = max(fallbackMinScale, resizeScale * 0.90)
            } catch {
                if isCancellationError(error) {
                    throw error
                }
                lastCompressionError = error
                let nsError = error as NSError
                Task {
                    await AppDiagnostics.shared.log(
                        level: "error",
                        category: "conversion",
                        message: "compatibility_retry_error",
                        context: .diagnostics(
                            ("attempt", "\(attempt)"),
                            ("error", error.localizedDescription),
                            ("errorDomain", nsError.domain),
                            ("errorCode", "\(nsError.code)")
                        )
                    )
                }

                // Encoder rejected settings: prefer stronger downscale, keep bitrate in a safer range.
                targetVideoBitrate = max(videoFloor, targetVideoBitrate)
                if sourceHasAudio {
                    targetAudioBitrate = max(audioFloor, Int(Double(targetAudioBitrate) * 0.92))
                }
                resizeScale = max(fallbackMinScale, resizeScale * 0.82)
            }
        }

        try throwIfCancellationRequested()
        statusMessage = L10n.tr("Trying system fallback exporter...")
        conversionProgress = max(conversionProgress ?? 0, fallbackPhaseStart + fallbackPhaseWeight)
        do {
            let exportedWithAudioURL = try await compressionService.exportLowQualityFallback(
                sourceURL: sourceMetadata.sourceURL
            )
            let exportedWithAudioSize = try fileSize(for: exportedWithAudioURL)
            if exportedWithAudioSize <= targetBytes {
                return exportedWithAudioURL
            }
            bestSeenBytes = min(bestSeenBytes, exportedWithAudioSize)

            let tightened = try await retryOversizedSystemExportWithAudio(
                exportedURL: exportedWithAudioURL,
                targetBytes: targetBytes,
                initialBestOversizedBytes: bestSeenBytes
            )
            bestSeenBytes = tightened.bestOversizedBytes
            if let tightenedURL = tightened.outputURL {
                try? FileManager.default.removeItem(at: exportedWithAudioURL)
                return tightenedURL
            }
            if let retryError = tightened.lastError {
                lastCompressionError = retryError
            }
            try? FileManager.default.removeItem(at: exportedWithAudioURL)

            Task {
                await AppDiagnostics.shared.log(
                    level: "warn",
                    category: "conversion",
                    message: "system_export_fallback_oversized",
                    context: .diagnostics(
                        ("targetBytes", "\(targetBytes)"),
                        ("withAudioBytes", "\(exportedWithAudioSize)")
                    )
                )
            }
        } catch {
            if isCancellationError(error) {
                throw error
            }
            if lastCompressionError == nil {
                lastCompressionError = error
            }
            let nsError = error as NSError
            Task {
                await AppDiagnostics.shared.log(
                    level: "error",
                    category: "conversion",
                    message: "system_export_fallback_failed",
                    context: .diagnostics(
                        ("error", error.localizedDescription),
                        ("errorDomain", nsError.domain),
                        ("errorCode", "\(nsError.code)")
                    )
                )
            }
        }

        if let lastCompressionError {
            throw lastCompressionError
        }

        let bestResult = bestSeenBytes == .max ? targetBytes : bestSeenBytes
        throw ConversionTargetError.unableToReachTarget(
            targetBytes: targetBytes,
            bestBytes: bestResult
        )
    }

    private func retryOversizedSystemExportWithAudio(
        exportedURL: URL,
        targetBytes: Int64,
        initialBestOversizedBytes: Int64
    ) async throws -> (outputURL: URL?, bestOversizedBytes: Int64, lastError: Error?) {
        let exportedMetadata = try await metadataInspector.inspect(url: exportedURL)
        let duration = max(exportedMetadata.durationSeconds, 0.001)
        let totalBitrateBudget = max(96_000, Int((Double(targetBytes) * 8 / duration) * 0.985))
        let sourceHasAudio = exportedMetadata.sourceAudioBitrate > 0
        let lowTargetMode = totalBitrateBudget < 180_000 || duration < 30
        let fallbackMinScale = 0.25
        let audioFloor = lowTargetMode ? 12_000 : 16_000
        let videoFloor = lowTargetMode ? 105_000 : 70_000

        var targetAudioBitrate: Int
        if sourceHasAudio {
            let preferredAudio = min(max(16_000, exportedMetadata.sourceAudioBitrate), 48_000)
            let budgetLimitedAudio = max(16_000, totalBitrateBudget / 3)
            targetAudioBitrate = min(preferredAudio, budgetLimitedAudio)
            if lowTargetMode {
                targetAudioBitrate = min(targetAudioBitrate, max(audioFloor, totalBitrateBudget / 5))
            }
        } else {
            targetAudioBitrate = 0
        }

        var targetVideoBitrate = max(videoFloor, totalBitrateBudget - targetAudioBitrate)
        var resizeScale = 0.86
        var bestSeenBytes = initialBestOversizedBytes
        var lastError: Error?
        let maxAttempts = 10
        let progressStart = 0.95
        let progressWeight = 0.045
        let attemptWeight = progressWeight / Double(maxAttempts)

        for attempt in 1...maxAttempts {
            try throwIfCancellationRequested()
            conversionProgress = max(conversionProgress ?? 0, progressStart + (Double(attempt - 1) * attemptWeight))
            let attemptVideoBitrate = targetVideoBitrate
            let attemptAudioBitrate = targetAudioBitrate
            let attemptResizeScale = resizeScale
            Task {
                await AppDiagnostics.shared.log(
                    level: "warn",
                    category: "conversion",
                    message: "system_export_audio_retry_attempt",
                    context: .diagnostics(
                        ("attempt", "\(attempt)"),
                        ("maxAttempts", "\(maxAttempts)"),
                        ("targetBytes", "\(targetBytes)"),
                        ("videoBitrate", "\(attemptVideoBitrate)"),
                        ("audioBitrate", "\(attemptAudioBitrate)"),
                        ("resizeScale", String(format: "%.4f", attemptResizeScale))
                    )
                )
            }

            let plan = CompressionPlan(
                targetBytes: targetBytes,
                outputContainer: .mp4,
                outputCodec: .h264,
                targetVideoBitrate: targetVideoBitrate,
                targetAudioBitrate: targetAudioBitrate,
                resizeScale: resizeScale,
                estimatedOutputBytes: targetBytes,
                reason: "System fallback audio-preserving retry"
            )

            do {
                let outputURL = try await compressionService.compress(
                    sourceURL: exportedURL,
                    metadata: exportedMetadata,
                    plan: plan,
                    removeHDR: true,
                    progressHandler: { [weak self] progress in
                        Task { @MainActor in
                            let normalized = min(max(progress, 0), 1)
                            let mapped = progressStart + (Double(attempt - 1) * attemptWeight) + (normalized * attemptWeight)
                            self?.conversionProgress = max(self?.conversionProgress ?? 0, mapped)
                        }
                    }
                )

                let outputSize = try fileSize(for: outputURL)
                if outputSize <= targetBytes {
                    return (outputURL, min(bestSeenBytes, outputSize), lastError)
                }

                bestSeenBytes = min(bestSeenBytes, outputSize)
                try? FileManager.default.removeItem(at: outputURL)

                targetVideoBitrate = max(videoFloor, Int(Double(targetVideoBitrate) * 0.92))
                if sourceHasAudio {
                    targetAudioBitrate = max(audioFloor, Int(Double(targetAudioBitrate) * 0.90))
                }
                resizeScale = max(fallbackMinScale, resizeScale * 0.88)
            } catch {
                if isCancellationError(error) {
                    throw error
                }
                lastError = error
                let nsError = error as NSError
                Task {
                    await AppDiagnostics.shared.log(
                        level: "error",
                        category: "conversion",
                        message: "system_export_audio_retry_error",
                        context: .diagnostics(
                            ("attempt", "\(attempt)"),
                            ("error", error.localizedDescription),
                            ("errorDomain", nsError.domain),
                            ("errorCode", "\(nsError.code)")
                        )
                    )
                }

                targetVideoBitrate = max(videoFloor, targetVideoBitrate)
                if sourceHasAudio {
                    targetAudioBitrate = max(audioFloor, Int(Double(targetAudioBitrate) * 0.95))
                }
                resizeScale = max(fallbackMinScale, resizeScale * 0.80)
            }
        }

        return (nil, bestSeenBytes, lastError)
    }

    private func refreshEstimatedPlan() {
        guard let sourceMetadata else {
            estimatedOutputBytes = nil
            estimatedPlanReason = nil
            return
        }

        guard let settings = try? currentSettings(), validationMessage == nil else {
            estimatedOutputBytes = nil
            estimatedPlanReason = nil
            return
        }

        let supportedFormats = self.supportedOutputFormats.isEmpty
            ? CompressionContainer.preferredAutoOrder
            : self.supportedOutputFormats

        guard let plan = try? planner.makePlan(
            source: sourceMetadata.sourceProfile,
            settings: settings,
            supportedOutputFormats: supportedFormats
        ) else {
            estimatedOutputBytes = nil
            estimatedPlanReason = nil
            return
        }

        estimatedOutputBytes = plan.estimatedOutputBytes
        estimatedPlanReason = plan.reason
    }

    private func refreshMonetizationState() async {
        purchaseOptions = await purchaseManager.loadPlanOptions()
        hasPremiumAccess = await purchaseManager.hasActiveEntitlement()
        refreshQuotaStatusMessage()
    }

    private func refreshQuotaStatusMessage() {
        if hasPremiumAccess {
            quotaStatusMessage = ""
            return
        }

        let remaining = quotaStore.remainingFreeConversionsToday()
        quotaStatusMessage = remaining > 0
            ? L10n.tr("One conversion left today.")
            : L10n.tr("No conversions left today.")
    }

    private func fileSize(for url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .fileAllocatedSizeKey])
        return Int64(values.fileSize ?? values.fileAllocatedSize ?? 0)
    }

    private func suggestedTarget(fromSourceBytes sourceBytes: Int64) -> (value: Double, unit: CompressionUnit) {
        let targetBytes = max(1, sourceBytes / 2)
        let unit: CompressionUnit
        if targetBytes >= Int64(CompressionUnit.mb.multiplier) {
            unit = .mb
        } else {
            unit = .kb
        }

        let rawValue = Double(targetBytes) / unit.multiplier
        let rounded = (rawValue * 100).rounded() / 100
        return (value: max(0.01, rounded), unit: unit)
    }

    private func buildResolutionOptions(from metadata: VideoMetadata) -> [ResolutionOption] {
        let candidateScales: [Double] = [1.0, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.33]
        var options: [ResolutionOption] = []
        var seenDimensions = Set<String>()

        for scale in candidateScales {
            let width = makeEven(Int((Double(metadata.width) * scale).rounded()))
            let height = makeEven(Int((Double(metadata.height) * scale).rounded()))
            guard width <= metadata.width, height <= metadata.height else {
                continue
            }

            let id = "\(width)x\(height)"
            guard !seenDimensions.contains(id) else {
                continue
            }
            seenDimensions.insert(id)

            let title: String
            if options.isEmpty {
                title = L10n.fmt("Same as source (%dx%d, 0%% smaller)", width, height)
            } else {
                title = L10n.fmt("%dx%d (%@)", width, height, reductionLabel(for: scale))
            }

            options.append(ResolutionOption(id: id, title: title, scale: scale))
        }

        if options.isEmpty {
            options.append(
                ResolutionOption(
                    id: "\(metadata.width)x\(metadata.height)",
                    title: L10n.fmt("Same as source (%dx%d, 0%% smaller)", metadata.width, metadata.height),
                    scale: 1.0
                )
            )
        }

        return options
    }

    private func reductionLabel(for scale: Double) -> String {
        let reductionPercent = Int(((1 - scale) * 100).rounded())
        return L10n.fmt("%d%% smaller", max(0, reductionPercent))
    }

    private func launchShowcaseStep() -> ShowcaseStep? {
        let args = ProcessInfo.processInfo.arguments
        guard let keyIndex = args.firstIndex(of: "-uiShowcaseStep") else {
            return nil
        }
        let valueIndex = args.index(after: keyIndex)
        guard valueIndex < args.endIndex else {
            return nil
        }
        return ShowcaseStep(rawValue: args[valueIndex].lowercased())
    }

    private func applyShowcaseState(_ step: ShowcaseStep) {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("showcase-source.mov")
        let metadata = VideoMetadata(
            sourceURL: sourceURL,
            durationSeconds: 18.2,
            fileSizeBytes: 42 * 1_024 * 1_024,
            width: 1080,
            height: 1920,
            frameRate: 30,
            hasHDR: false,
            container: .mov,
            codec: .h264,
            sourceVideoBitrate: 11_200_000,
            sourceAudioBitrate: 128_000,
            preferredTransform: .identity
        )

        hasPremiumAccess = true
        quotaStatusMessage = L10n.tr("Premium active: unlimited conversions.")
        purchaseOptions = []
        errorMessage = nil
        isPaywallPresented = false

        switch step {
        case .source:
            workflowStep = .source
            sourceMetadata = nil
            sourcePreviewImage = nil
            sourceQuickInfoText = nil
            statusMessage = L10n.tr("Pick a video from your gallery or Files to start.")
            isConverting = false
            conversionProgress = nil
            hasStartedConversion = false
        case .settings:
            workflowStep = .settings
            sourceMetadata = metadata
            sourcePreviewImage = makeShowcasePreviewImage()
            sourceQuickInfoText = L10n.fmt("Detected: %@ • %@", "MOV", humanReadableSize(metadata.fileSizeBytes))
            supportedOutputFormats = [.mov, .mp4, .m4v, .gpp3, .gpp23]
            targetUnit = .mb
            targetValueText = "21"
            statusMessage = L10n.fmt("Video loaded. Suggested target: %@ %@ (~2x smaller).", "21", "MB")
            isLoadingSourceDetails = false
            isLoadingOutputFormats = false
            isConverting = false
            conversionProgress = nil
            hasStartedConversion = false
            estimatedOutputBytes = Int64(20.6 * 1_024 * 1_024)
        case .convert:
            workflowStep = .conversion
            sourceMetadata = metadata
            sourcePreviewImage = makeShowcasePreviewImage()
            sourceQuickInfoText = L10n.fmt("Detected: %@ • %@", "MOV", humanReadableSize(metadata.fileSizeBytes))
            supportedOutputFormats = [.mov, .mp4, .m4v, .gpp3, .gpp23]
            targetUnit = .mb
            targetValueText = "21"
            isLoadingSourceDetails = false
            isLoadingOutputFormats = false
            hasStartedConversion = true
            isConverting = true
            isCancellingConversion = false
            conversionProgress = 0.47
            estimatedOutputBytes = Int64(20.6 * 1_024 * 1_024)
            statusMessage = L10n.tr("Starting first conversion pass...")
        }

        validateTarget()
    }

    private func makeShowcasePreviewImage() -> UIImage {
        let size = CGSize(width: 420, height: 420)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            let colors = [UIColor.systemBlue.cgColor, UIColor.systemTeal.cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            let iconConfig = UIImage.SymbolConfiguration(pointSize: 88, weight: .bold)
            let icon = UIImage(systemName: "play.rectangle.fill", withConfiguration: iconConfig)?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
            let iconRect = CGRect(x: 130, y: 130, width: 160, height: 160)
            icon?.draw(in: iconRect)

            context.cgContext.setStrokeColor(UIColor.white.withAlphaComponent(0.35).cgColor)
            context.cgContext.setLineWidth(10)
            context.cgContext.stroke(rect.insetBy(dx: 12, dy: 12))
        }
    }
}
