import AVFoundation
import Combine
import Foundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class VideoCompressionViewModel: ObservableObject {
    private enum ShowcaseStep: String {
        case source
        case settings
        case convert
    }

    private enum SourceLoadError: LocalizedError {
        case noVideoSelected

        var errorDescription: String? {
            switch self {
            case .noVideoSelected:
                return L10n.tr("No video was selected.")
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

    private let settingsStore = CompressionSettingsStore()
    private let quotaStore = ConversionQuotaStore()
    private let purchaseManager = PurchaseManager()
    private let metadataInspector = VideoMetadataInspector()
    private let compressionService = VideoCompressionService()
    private let planner = CompressionPlanner()

    private var restoringSettings = false
    private var currentLoadRequestID = UUID()

    init() {
        loadSettings()
        refreshQuotaStatusMessage()
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
        estimatedOutputBytes = nil
        estimatedPlanReason = nil
        refreshQuotaStatusMessage()
        workflowStep = .source
    }

    var formatOptions: [OutputFormatOption] {
        var options: [OutputFormatOption] = [OutputFormatOption(id: OutputFormatOption.autoID, title: L10n.tr("Same as source"))]
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

    var conversionProgressPercentText: String? {
        guard let conversionProgress else { return nil }
        return "\(Int((conversionProgress * 100).rounded()))%"
    }

    var sliderRange: ClosedRange<Double> {
        let minimumForUnit = defaultSliderMinimum(for: targetUnit)
        let maximumForUnit = defaultSliderMaximum(for: targetUnit)

        guard let sourceMetadata else {
            return minimumForUnit...maximumForUnit
        }

        let minimumBytes = Int64(
            (Double(sourceMetadata.fileSizeBytes) / CompressionPlanner.maxCompressionRatio).rounded(.up)
        )
        let sourceValueInUnit = Double(sourceMetadata.fileSizeBytes) / targetUnit.multiplier
        let minimumValue = max(minimumForUnit, Double(minimumBytes) / targetUnit.multiplier).rounded(.up)
        let maximumValue = max(minimumValue + defaultSliderStep(for: targetUnit), sourceValueInUnit.rounded(.up))
        return minimumValue...maximumValue
    }

    var sliderStep: Double {
        defaultSliderStep(for: targetUnit)
    }

    var targetSliderValue: Double {
        get {
            let value = parsedTargetValue() ?? sliderRange.lowerBound
            return clamp(value, to: sliderRange).rounded()
        }
        set {
            let integerValue = Int(clamp(newValue, to: sliderRange).rounded())
            targetValueText = String(integerValue)
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
            try await processSelectedSource(url: sourceURL, requestID: requestID)
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
        errorMessage = error.localizedDescription
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

        guard let pickedVideo = try await pickerItem.loadTransferable(type: PickedVideo.self) else {
            throw SourceLoadError.noVideoSelected
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
        isCancellingConversion = false
        conversionProgress = 0
        statusMessage = L10n.tr("Starting first conversion pass...")
        settingsStore.save(settings)

        do {
            let firstPlan = try planner.makePlan(
                source: sourceMetadata.sourceProfile,
                settings: settings,
                supportedOutputFormats: supportedOutputFormats
            )

            let firstOutputURL = try await compressionService.compress(
                sourceURL: sourceMetadata.sourceURL,
                metadata: sourceMetadata,
                plan: firstPlan,
                removeHDR: settings.removeHDR,
                progressHandler: { [weak self] progress in
                    Task { @MainActor in
                        self?.conversionProgress = progress
                    }
                }
            )

            let firstOutputSize = try fileSize(for: firstOutputURL)
            if firstOutputSize > firstPlan.targetBytes {
                didRetryConversion = true
                conversionProgress = 0
                statusMessage = L10n.tr("First output was larger than target. Starting second conversion...")

                let retryPlan = try planner.makeRetryPlan(
                    source: sourceMetadata.sourceProfile,
                    priorPlan: firstPlan,
                    settings: settings,
                    supportedOutputFormats: supportedOutputFormats
                )

                let retryOutputURL = try await compressionService.compress(
                    sourceURL: sourceMetadata.sourceURL,
                    metadata: sourceMetadata,
                    plan: retryPlan,
                    removeHDR: settings.removeHDR,
                    progressHandler: { [weak self] progress in
                        Task { @MainActor in
                            self?.conversionProgress = progress
                        }
                    }
                )

                try? FileManager.default.removeItem(at: firstOutputURL)

                convertedVideoURL = retryOutputURL
                convertedFileSizeBytes = try fileSize(for: retryOutputURL)
            } else {
                convertedVideoURL = firstOutputURL
                convertedFileSizeBytes = firstOutputSize
            }

            if !hasPremiumAccess {
                quotaStore.recordFreeConversionToday()
                refreshQuotaStatusMessage()
            }

            if let convertedFileSizeBytes,
               let sourceBytes = sourceMetadata.fileSizeBytes as Int64?
            {
                statusMessage = L10n.fmt(
                    "Done. Output size: %@ (source: %@).",
                    humanReadableSize(convertedFileSizeBytes),
                    humanReadableSize(sourceBytes)
                )
            } else {
                statusMessage = L10n.tr("Done.")
            }
            conversionProgress = 1
        } catch {
            if case VideoCompressionServiceError.cancelled = error {
                statusMessage = L10n.tr("Conversion cancelled.")
                errorMessage = nil
                conversionProgress = nil
            } else {
                statusMessage = L10n.tr("Conversion failed.")
                errorMessage = error.localizedDescription
                conversionProgress = nil
            }
        }

        refreshQuotaStatusMessage()
        isCancellingConversion = false
        isConverting = false
    }

    func cancelConversion() {
        guard isConverting else { return }
        guard !isCancellingConversion else { return }

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

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: convertedVideoURL)
            }
            statusMessage = L10n.tr("Saved to Photo Library.")
        } catch {
            errorMessage = L10n.fmt("Failed to save to Photo Library: %@", error.localizedDescription)
        }
    }

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
            quotaStatusMessage = L10n.tr("Premium active: unlimited conversions.")
            return
        }

        let remaining = quotaStore.remainingFreeConversionsToday()
        quotaStatusMessage = L10n.fmt(
            "Free plan: %d of %d conversions left today.",
            remaining,
            ConversionQuotaStore.dailyFreeLimit
        )
    }

    private func fileSize(for url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .fileAllocatedSizeKey])
        return Int64(values.fileSize ?? values.fileAllocatedSize ?? 0)
    }

    private func suggestedTarget(fromSourceBytes sourceBytes: Int64) -> (value: Double, unit: CompressionUnit) {
        let targetBytes = max(1, sourceBytes / 2)
        let unit: CompressionUnit
        if targetBytes >= Int64(CompressionUnit.gb.multiplier) {
            unit = .gb
        } else if targetBytes >= Int64(CompressionUnit.mb.multiplier) {
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
