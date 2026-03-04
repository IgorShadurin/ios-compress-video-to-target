import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    private enum SettingsShowcaseVariant: String {
        case advancedBottom = "advanced-bottom"
        case formatDropdown = "format-dropdown"
        case resolutionDropdown = "resolution-dropdown"
    }

    private static let showcaseStepArgument: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let keyIndex = args.firstIndex(of: "-uiShowcaseStep") else {
            return nil
        }
        let valueIndex = args.index(after: keyIndex)
        guard valueIndex < args.endIndex else {
            return nil
        }
        return args[valueIndex].lowercased()
    }()
    private static let showcaseVariantArgument: SettingsShowcaseVariant? = {
        let args = ProcessInfo.processInfo.arguments
        guard let keyIndex = args.firstIndex(of: "-uiShowcaseVariant") else {
            return nil
        }
        let valueIndex = args.index(after: keyIndex)
        guard valueIndex < args.endIndex else {
            return nil
        }
        return SettingsShowcaseVariant(rawValue: args[valueIndex].lowercased())
    }()
    private static let settingsBottomAnchorID = "settings-bottom-anchor"

    @StateObject private var viewModel = VideoCompressionViewModel()
    @State private var isAdvancedSettingsExpanded = false
    @State private var didConfigureShowcaseSettingsVariant = false
    @State private var shouldScrollToSettingsBottom = false
    @State private var isFileImporterPresented = false
    @State private var isSaveDestinationDialogPresented = false
    @State private var isFilesExportPickerPresented = false
    @State private var isStartOverDialogPresented = false
    @State private var isCancelConversionDialogPresented = false
    @State private var pendingStepNavigation: VideoCompressionViewModel.WorkflowStep?
    @State private var selectedPaywallPlanID: String?
    @State private var hasPresentedShowcaseDoneSheet = false
#if DEBUG
    @State private var isDebugResetDialogPresented = false
#endif
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                stepHeader

                Group {
                    switch viewModel.workflowStep {
                    case .source:
                        sourceStep
                    case .settings:
                        settingsStep
                    case .conversion:
                        conversionStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .background(pageBackground.ignoresSafeArea())
            .navigationTitle(L10n.tr("Compress to Target Size"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: viewModel.pickerItem) { _, _ in
            Task {
                await viewModel.handlePickerChange()
            }
        }
        .onAppear {
            presentShowcaseDoneSheetIfNeeded()
        }
        .onChange(of: viewModel.hasConversionSucceeded) { _, _ in
            presentShowcaseDoneSheetIfNeeded()
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                Task {
                    await viewModel.importFromFiles(url: url)
                }
            case let .failure(error):
                viewModel.handleFileImportFailure(error)
            }
        }
        .confirmationDialog(
            L10n.tr("Leave current step?"),
            isPresented: Binding(
                get: { pendingStepNavigation != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingStepNavigation = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button(confirmationActionLabel, role: .destructive) {
                navigateToPendingStep()
            }
            Button(L10n.tr("Cancel"), role: .cancel) {
                pendingStepNavigation = nil
            }
        } message: {
            Text(confirmationMessage)
        }
        .confirmationDialog(
            L10n.tr("Start with a new video?"),
            isPresented: $isStartOverDialogPresented,
            titleVisibility: .visible
        ) {
            Button(L10n.tr("Start over"), role: .destructive) {
                viewModel.startNewConversionFlow()
            }
            Button(L10n.tr("Cancel")) {
                isStartOverDialogPresented = false
            }
        } message: {
            Text(L10n.tr("Current conversion result will be cleared."))
        }
        .confirmationDialog(
            L10n.tr("Leave current step?"),
            isPresented: $isCancelConversionDialogPresented,
            titleVisibility: .visible
        ) {
            Button(L10n.tr("Cancel conversion"), role: .destructive) {
                viewModel.cancelConversion()
            }
            Button(L10n.tr("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("You will return to conversion."))
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.isPaywallPresented },
                set: { isPresented in
                    if isPresented {
                        viewModel.presentPaywall()
                    } else {
                        viewModel.dismissPaywall()
                    }
                }
            )
        ) {
            paywallSheet
        }
        .sheet(isPresented: $isSaveDestinationDialogPresented) {
            SaveDestinationSheet(
                onSaveToGallery: {
                    Task {
                        await viewModel.saveToPhotoLibrary()
                    }
                },
                onSaveToFiles: {
                    isFilesExportPickerPresented = true
                }
            )
            .presentationDetents([.height(318), .medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $isFilesExportPickerPresented) {
            if let convertedVideoURL = viewModel.convertedVideoURL {
                FilesExportPicker(url: convertedVideoURL) { result in
                    switch result {
                    case .success:
                        viewModel.didSaveToFiles()
                    case let .failure(error):
                        let nsError = error as NSError
                        if nsError.domain == NSCocoaErrorDomain,
                           nsError.code == CocoaError.userCancelled.rawValue
                        {
                            return
                        }
                        viewModel.handleSaveToFilesFailure(error)
                    }
                }
            } else {
                ContentUnavailableView(L10n.tr("No Converted Video"), systemImage: "video.slash")
            }
        }
        .alert(
            L10n.tr("Video saved"),
            isPresented: Binding(
                get: { viewModel.isSaveSuccessAlertPresented },
                set: { isPresented in
                    if !isPresented {
                        viewModel.dismissSaveSuccessAlert()
                    }
                }
            )
        ) {
            Button(L10n.tr("OK"), role: .cancel) {
                viewModel.dismissSaveSuccessAlert()
            }
        } message: {
            Text(viewModel.saveSuccessMessage ?? L10n.tr("Video saved successfully."))
        }
#if DEBUG
        .background(
            DebugShakeDetector {
                if !isDebugResetDialogPresented {
                    isDebugResetDialogPresented = true
                }
            }
        )
        .confirmationDialog(
            L10n.tr("Debug: reset limits?"),
            isPresented: $isDebugResetDialogPresented,
            titleVisibility: .visible
        ) {
            Button(L10n.tr("Reset"), role: .destructive) {
                viewModel.debugResetLimitsForTesting()
            }
            Button(L10n.tr("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("This is available only in Debug builds."))
        }
#endif
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(VideoCompressionViewModel.WorkflowStep.allCases, id: \.rawValue) { step in
                    let isCurrent = step == viewModel.workflowStep
                    let isCompleted = step.rawValue < viewModel.workflowStep.rawValue

                    if step != .source {
                        Capsule()
                            .fill((isCurrent || isCompleted) ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.25))
                            .frame(height: 2)
                    }

                    Button {
                        requestStepNavigation(to: step)
                    } label: {
                        Text("\(step.rawValue)")
                            .font(.footnote.weight(.bold))
                            .frame(width: 40, height: 40)
                            .foregroundStyle(isCurrent || isCompleted ? .white : .secondary)
                            .background(
                                Circle().fill(isCurrent || isCompleted ? Color.accentColor : Color.secondary.opacity(0.2))
                            )
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(canNavigateToStep(step))
                }
            }

            Text(
                L10n.fmt(
                    "Step %d: %@",
                    viewModel.workflowStep.rawValue,
                    viewModel.workflowStep.shortTitle
                )
            )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var sourceStep: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !viewModel.hasPremiumAccess {
                    Button {
                        viewModel.presentPaywall()
                    } label: {
                        upgradeButtonLabel(style: .primary)
                    }
                    .buttonStyle(.plain)
                }

                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: heroGradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(L10n.tr("Select Source Video"))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text(L10n.tr("Choose from your gallery or Files."))
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                    if viewModel.hasPremiumAccess {
                        premiumSourceBadge
                            .padding(.top, 12)
                            .padding(.trailing, 12)
                    }
                }
                .frame(height: 168)

                HStack(spacing: 10) {
                    PhotosPicker(
                        selection: $viewModel.pickerItem,
                        matching: .videos,
                        preferredItemEncoding: .current,
                        photoLibrary: .shared()
                    ) {
                        Label(L10n.tr("Gallery"), systemImage: "photo.on.rectangle")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        isFileImporterPresented = true
                    } label: {
                        Label(L10n.tr("Files"), systemImage: "folder")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                }

                Text(L10n.tr("Processed locally on this device."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if viewModel.hasPremiumAccess {
                    manageSubscriptionsInlineButton
                } else {
                    quotaStatusCard
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color(uiColor: .systemRed))
                }
            }
            .padding(.top, 8)
        }
    }

    private var settingsStep: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    sourceCompactCard
                    if !viewModel.hasPremiumAccess && viewModel.canUseFreeConversionToday {
                        quotaStatusCard
                    }

                    if !viewModel.hasPremiumAccess && viewModel.canUseFreeConversionToday {
                        Button {
                            viewModel.presentPaywall()
                        } label: {
                            upgradeButtonLabel(style: .secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    if viewModel.isLoadingSourceDetails {
                        loadingCard
                    }

                    if viewModel.sourceMetadata != nil {
                        targetSettingsCard

                        if isFreeQuotaExhausted {
                            freeLimitReachedActionArea
                        } else {
                            Button {
                                Task {
                                    await viewModel.convert()
                                }
                            } label: {
                                Label(L10n.tr("Start Conversion"), systemImage: "play.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!viewModel.canConvert)
                        }

                        advancedOptionsSection
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color(uiColor: .systemRed))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.settingsBottomAnchorID)
                }
                .padding(.bottom, 16)
            }
            .onAppear {
                applySettingsShowcaseVariantIfNeeded()
                scrollToShowcaseSettingsBottomIfNeeded(proxy)
            }
            .onChange(of: isAdvancedSettingsExpanded) { _, _ in
                scrollToShowcaseSettingsBottomIfNeeded(proxy)
            }
        }
    }

    private var isFreeQuotaExhausted: Bool {
        !viewModel.hasPremiumAccess && !viewModel.canUseFreeConversionToday
    }

    private var freeLimitReachedActionArea: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(L10n.tr("No conversions left today."))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )

            Button {
                viewModel.presentPaywall()
            } label: {
                upgradeButtonLabel(style: .secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var sourceCompactCard: some View {
        HStack(spacing: 12) {
            Group {
                if let sourcePreviewImage = viewModel.sourcePreviewImage {
                    Image(uiImage: sourcePreviewImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(Color.secondary.opacity(0.12))
                        Image(systemName: "video")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("Source Preview"))
                    .font(.subheadline.weight(.semibold))
                if let sourceQuickInfoText = viewModel.sourceQuickInfoText {
                    Text(sourceQuickInfoText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let sourceSummaryText = viewModel.sourceSummaryText {
                    Text(sourceSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let sourceSizeText = viewModel.sourceSizeText {
                    Text(L10n.fmt("Size: %@", sourceSizeText))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(cardBackground)
    }

    private var loadingCard: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
            Text(L10n.tr("Loading video details..."))
                .font(.headline)
            Text(viewModel.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(cardBackground)
    }

    private var targetSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("Target Settings"))
                .font(.headline)

            HStack(spacing: 8) {
                TextField(L10n.tr("Target size"), text: $viewModel.targetValueText)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.45 : 0.2), lineWidth: 1)
                    )

                Picker(L10n.tr("Unit"), selection: $viewModel.targetUnit) {
                    ForEach(viewModel.availableTargetUnits, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .pickerStyle(.menu)
            }

            Slider(
                value: $viewModel.targetSliderValue,
                in: viewModel.sliderRange,
                step: viewModel.sliderStep
            )

            HStack {
                Text("\(viewModel.sliderMinLabel) \(viewModel.targetUnit.label)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.sliderMaxLabel) \(viewModel.targetUnit.label)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if viewModel.isLoadingOutputFormats {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.tr("Checking format compatibility..."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let validationMessage = viewModel.validationMessage {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .systemRed))
            }

            Text(L10n.tr("Compression cannot exceed 30x reduction from source size."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(cardBackground)
    }

    private var conversionStep: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 12) {
                    if viewModel.isConverting {
                        if let progress = viewModel.conversionProgress {
                            ProgressView(value: progress, total: 1)
                                .progressViewStyle(.linear)
                                .tint(.accentColor)

                            if let progressText = viewModel.conversionProgressPercentText {
                                Text(progressText)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ProgressView()
                                .controlSize(.large)
                        }
                    } else if viewModel.hasConversionSucceeded {
                        conversionSuccessIcon
                    } else if viewModel.hasConversionFailed {
                        conversionFailureIcon
                    } else {
                        Image(systemName: "hourglass")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(conversionTitle)
                        .font(.headline)

                    if let conversionSubtitle {
                        Text(conversionSubtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if viewModel.isConverting {
                        Button(role: .destructive) {
                            isCancelConversionDialogPresented = true
                        } label: {
                            HStack(spacing: 10) {
                                if viewModel.isCancellingConversion {
                                    ProgressView()
                                        .tint(cancelConversionAccent)
                                        .frame(width: 18, height: 18)
                                } else {
                                    Image(systemName: "xmark.octagon.fill")
                                        .font(.headline)
                                        .foregroundStyle(cancelConversionAccent)
                                }

                                Text(viewModel.isCancellingConversion ? L10n.tr("Cancelling...") : L10n.tr("Cancel conversion"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(cancelConversionTextColor)

                                Spacer(minLength: 0)

                                Image(systemName: "hand.raised.fill")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(cancelConversionAccent.opacity(0.9))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(cancelConversionFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .stroke(cancelConversionStroke, lineWidth: 1)
                            )
                            .shadow(color: cancelConversionShadow, radius: 7, x: 0, y: 3)
                        }
                        .buttonStyle(.plain)
                        .disabled(!viewModel.canCancelConversion)
                        .opacity(viewModel.canCancelConversion ? 1 : 0.62)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(18)
                .background(cardBackground)

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.tr("Conversion Details"))
                        .font(.headline)

                    if let sourceSizeText = viewModel.sourceSizeText {
                        LabeledContent(L10n.tr("Original size")) {
                            Text(sourceSizeText)
                        }
                    }

                    if let targetSizeText = viewModel.targetSizeText {
                        LabeledContent(L10n.tr("Target size")) {
                            Text(targetSizeText)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(cardBackground)

                if viewModel.hasConversionFailed {
                    Button {
                        Task {
                            await viewModel.convert()
                        }
                    } label: {
                            Label(L10n.tr("Retry Conversion"), systemImage: "arrow.clockwise")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canConvert)
                }

                if let outputSizeText = viewModel.outputSizeText {
                    VStack(spacing: 12) {
                        LabeledContent(L10n.tr("Output size")) {
                            Text(outputSizeText)
                        }

                        Button {
                            isSaveDestinationDialogPresented = true
                        } label: {
                            Label(L10n.tr("Save Result"), systemImage: "square.and.arrow.down.on.square")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canSaveResult)

                        Button {
                            isStartOverDialogPresented = true
                        } label: {
                            Label(L10n.tr("New video"), systemImage: "repeat.circle")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(cardBackground)
                }

                if let errorMessage = viewModel.errorMessage,
                   !viewModel.isConverting
                {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color(uiColor: .systemRed))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private var conversionSuccessIcon: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(uiColor: .systemGreen),
                            Color(uiColor: .systemTeal)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 92, height: 92)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(.white)

            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .offset(x: 30, y: -28)
        }
        .shadow(color: Color(uiColor: .systemGreen).opacity(0.28), radius: 14, x: 0, y: 8)
    }

    private var conversionFailureIcon: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(uiColor: .systemRed),
                            Color(uiColor: .systemOrange)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 92, height: 92)

            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.white)
        }
        .shadow(color: Color(uiColor: .systemRed).opacity(0.25), radius: 14, x: 0, y: 8)
    }

    private var conversionTitle: String {
        if viewModel.isConverting {
            return L10n.tr("Converting video...")
        }
        if viewModel.hasConversionSucceeded {
            return L10n.tr("Conversion complete")
        }
        if viewModel.hasConversionFailed {
            return L10n.tr("Conversion failed")
        }
        return L10n.tr("Ready")
    }

    private var conversionSubtitle: String? {
        if viewModel.isConverting {
            return L10n.tr("Please do not close the app until conversion finishes.")
        }
        if viewModel.hasConversionSucceeded {
            return L10n.tr("Your video is ready. Choose where to save it.")
        }
        if viewModel.hasConversionFailed {
            return L10n.tr("We could not encode this video with current settings.")
        }
        return nil
    }

    private var quotaStatusCard: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.canUseFreeConversionToday ? "lock.open" : "lock.fill")
                .foregroundStyle(.secondary)
            Text(viewModel.quotaStatusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var premiumSourceBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "crown.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(uiColor: .systemYellow))
            Text(L10n.tr("Premium"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.28))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }

    private enum UpgradeCTAStyle {
        case primary
        case secondary
    }

    @ViewBuilder
    private func upgradeButtonLabel(style: UpgradeCTAStyle) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "crown.fill")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .systemYellow))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color(uiColor: .systemBackground).opacity(colorScheme == .dark ? 0.24 : 0.5))
                )

            Text(L10n.tr("Upgrade to Unlimited"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color(uiColor: .label))

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color(uiColor: .label).opacity(0.66))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(uiColor: .systemYellow).opacity(colorScheme == .dark ? 0.24 : 0.34),
                            Color(uiColor: .systemOrange).opacity(colorScheme == .dark ? 0.18 : 0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Group {
                        if style == .primary {
                            PremiumCTAPrimaryShimmer(cornerRadius: 16)
                        } else {
                            PremiumCTASecondaryShimmer(cornerRadius: 16)
                        }
                    }
                    .allowsHitTesting(false)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(uiColor: .systemYellow).opacity(colorScheme == .dark ? 0.5 : 0.65), lineWidth: 1)
                )
        )
        .shadow(color: Color(uiColor: .systemYellow).opacity(colorScheme == .dark ? 0.16 : 0.22), radius: 8, x: 0, y: 4)
    }

    private var paywallSheet: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: paywallBackgroundGradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        VStack(spacing: 10) {
                            Text(L10n.tr("Unlock Unlimited Conversions"))
                                .font(.title2.weight(.bold))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(paywallPrimaryTextColor)
                        }
                        .padding(.top, 8)

                        VStack(spacing: 14) {
                            ForEach(viewModel.purchaseOptions) { option in
                                paywallPlanCard(
                                    option: option,
                                    isSelected: option.id == selectedPaywallPlanID
                                )
                            }

                            if viewModel.purchaseOptions.isEmpty {
                                ProgressView()
                                    .tint(paywallPrimaryTextColor)
                                    .padding(.vertical, 8)
                            }
                        }

                        Button {
                            guard let selectedPaywallPlanID else { return }
                            Task {
                                await viewModel.purchasePlan(planID: selectedPaywallPlanID)
                            }
                        } label: {
                            Text(viewModel.isPurchasingPlan ? L10n.tr("Processing...") : L10n.tr("Continue"))
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .padding(.horizontal, 18)
                                .background(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0xFE / 255, green: 0x68 / 255, blue: 0x71 / 255),
                                            Color(red: 0xFF / 255, green: 0xA3 / 255, blue: 0x6B / 255)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(paywallCTAStrokeColor, lineWidth: 1)
                                )
                                .shadow(color: paywallCTAShadowColor, radius: 14, x: 0, y: 10)
                        }
                        .buttonStyle(.plain)
                        .disabled(
                            viewModel.isPurchasingPlan || selectedPaywallPlanID == nil
                        )

                        Button {
                            Task {
                                await viewModel.restorePurchases()
                            }
                        } label: {
                            Text(L10n.tr("Restore Purchases"))
                                .font(.subheadline.weight(.semibold))
                                .underline()
                                .foregroundStyle(paywallPrimaryTextColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isPurchasingPlan)

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(Color(uiColor: .systemRed))
                                .multilineTextAlignment(.center)
                        }

                        VStack(spacing: 6) {
                            Text(L10n.tr("Auto-renewable plans renew unless canceled 24 hours before period end."))
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(paywallTertiaryTextColor)
                            HStack(spacing: 14) {
                                if let termsOfUseURL {
                                    Link("Terms", destination: termsOfUseURL)
                                }
                                if let privacyPolicyURL {
                                    Link("Privacy", destination: privacyPolicyURL)
                                }
                            }
                            .font(.caption2.weight(.semibold))
                            .tint(paywallPrimaryTextColor)

                            if let manageSubscriptionsURL {
                                Link(L10n.tr("You can manage subscriptions in Apple ID settings."), destination: manageSubscriptionsURL)
                                    .font(.caption2.weight(.semibold))
                                    .underline()
                                    .multilineTextAlignment(.center)
                                    .tint(paywallPrimaryTextColor)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 30)
                }
            }
            .onAppear {
                normalizeSelectedPaywallSelection()
            }
            .onChange(of: viewModel.purchaseOptions) { _, _ in
                normalizeSelectedPaywallSelection()
            }
            .navigationTitle(L10n.tr("Premium"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.dismissPaywall()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(paywallSecondaryTextColor)
                    }
                }
            }
        }
    }

    private func preferredPaywallPlanID() -> String? {
        if viewModel.purchaseOptions.contains(where: { $0.id == PurchaseManager.monthlyProductID && $0.isAvailable }) {
            return PurchaseManager.monthlyProductID
        }
        if viewModel.purchaseOptions.contains(where: { $0.id == PurchaseManager.lifetimeProductID && $0.isAvailable }) {
            return PurchaseManager.lifetimeProductID
        }
        if viewModel.purchaseOptions.contains(where: { $0.id == PurchaseManager.weeklyProductID && $0.isAvailable }) {
            return PurchaseManager.weeklyProductID
        }

        if viewModel.purchaseOptions.contains(where: { $0.id == PurchaseManager.monthlyProductID }) {
            return PurchaseManager.monthlyProductID
        }
        if viewModel.purchaseOptions.contains(where: { $0.id == PurchaseManager.lifetimeProductID }) {
            return PurchaseManager.lifetimeProductID
        }
        if viewModel.purchaseOptions.contains(where: { $0.id == PurchaseManager.weeklyProductID }) {
            return PurchaseManager.weeklyProductID
        }

        return viewModel.purchaseOptions.first?.id
    }

    private var selectedFormatTitle: String {
        viewModel.formatOptions.first(where: { $0.id == viewModel.selectedOutputFormatID })?.title
            ?? L10n.tr("Auto")
    }

    private var selectedResolutionTitle: String {
        viewModel.resolutionOptions.first(where: { abs($0.scale - viewModel.selectedResolutionScale) < 0.0001 })?.title
            ?? L10n.tr("Same as source")
    }

    private var termsOfUseURL: URL? {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "TERMS_OF_USE_URL") as? String,
           let url = URL(string: configured), !configured.isEmpty
        {
            return url
        }
        return URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    }

    private var privacyPolicyURL: URL? {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "PRIVACY_POLICY_URL") as? String,
           let url = URL(string: configured), !configured.isEmpty
        {
            return url
        }
        return nil
    }

    private var manageSubscriptionsURL: URL? {
        URL(string: "https://apps.apple.com/account/subscriptions")
    }

    @ViewBuilder
    private var manageSubscriptionsInlineButton: some View {
        Button {
            openManageSubscriptions()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                Text(L10n.tr("You can manage subscriptions in Apple ID settings."))
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right.square")
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(Color(uiColor: .secondaryLabel))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.45 : 0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func openManageSubscriptions() {
        if let manageSubscriptionsURL {
            openURL(manageSubscriptionsURL)
        }
    }

    private var advancedOptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isAdvancedSettingsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Label(L10n.tr("Advanced options"), systemImage: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(uiColor: .label))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isAdvancedSettingsExpanded ? 180 : 0))
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)

            if isAdvancedSettingsExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    settingsDropdownField(
                        value: selectedFormatTitle,
                        showcaseExpanded: showcaseSettingsVariant == .formatDropdown,
                        showcaseOptions: viewModel.formatOptions.map(\.title)
                    ) {
                        ForEach(viewModel.formatOptions, id: \.id) { option in
                            Button {
                                viewModel.selectedOutputFormatID = option.id
                            } label: {
                                dropdownOptionLabel(
                                    title: option.title,
                                    isSelected: option.id == viewModel.selectedOutputFormatID
                                )
                            }
                        }
                    }
                    .padding(.top, 6)

                    Toggle(L10n.tr("Adjust resolution"), isOn: $viewModel.allowResizeUpTo10x)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))

                    if viewModel.allowResizeUpTo10x {
                        settingsDropdownField(
                            title: L10n.tr("Output resolution"),
                            value: selectedResolutionTitle,
                            showcaseExpanded: showcaseSettingsVariant == .resolutionDropdown,
                            showcaseOptions: viewModel.resolutionOptions.map(\.title)
                        ) {
                            ForEach(viewModel.resolutionOptions, id: \.id) { option in
                                Button {
                                    viewModel.selectedResolutionScale = option.scale
                                } label: {
                                    dropdownOptionLabel(
                                        title: option.title,
                                        isSelected: abs(option.scale - viewModel.selectedResolutionScale) < 0.0001
                                    )
                                }
                            }
                        }
                    }

                    Divider()
                        .overlay(Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.4 : 0.25))

                    Toggle(L10n.tr("Remove HDR"), isOn: $viewModel.removeHDR)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.45 : 0.22), lineWidth: 1)
        )
    }

    private func settingsDropdownField<MenuContent: View>(
        title: String? = nil,
        value: String,
        showcaseExpanded: Bool = false,
        showcaseOptions: [String] = [],
        @ViewBuilder menuContent: () -> MenuContent
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Menu {
                menuContent()
            } label: {
                HStack(spacing: 8) {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .label))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(uiColor: .systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.65 : 0.42), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if showcaseExpanded {
                showcaseDropdownPreview(options: showcaseOptions, selectedValue: value)
            }
        }
    }

    private func showcaseDropdownPreview(options: [String], selectedValue: String) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(options.prefix(6)).indices, id: \.self) { index in
                let option = options[index]
                HStack(spacing: 8) {
                    Text(option)
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .label))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if option == selectedValue {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)

                if index < min(options.count, 6) - 1 {
                    Divider()
                        .overlay(Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.45 : 0.22))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.65 : 0.30), lineWidth: 1)
        )
    }

    private func dropdownOptionLabel(title: String, isSelected: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }

    private func normalizeSelectedPaywallSelection() {
        if let selectedPaywallPlanID,
           viewModel.purchaseOptions.contains(where: { $0.id == selectedPaywallPlanID })
        {
            return
        }
        selectedPaywallPlanID = preferredPaywallPlanID()
    }

    private func paywallPlanCard(option: PurchasePlanOption, isSelected: Bool) -> some View {
        let accent = paywallAccent(for: option.id)
        return Button {
            selectedPaywallPlanID = option.id
        } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(option.title)
                            .font(.headline)
                            .foregroundStyle(paywallPrimaryTextColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .layoutPriority(1)
                        if let badge = paywallBadge(for: option.id) {
                            paywallBadgeChip(
                                title: badge,
                                fill: accent.opacity(0.9),
                                stroke: Color.white.opacity(0.35),
                                textColor: .white,
                                showsStroke: true
                            )
                        }
                        if !option.isAvailable {
                            paywallBadgeChip(
                                title: L10n.tr("Unavailable"),
                                fill: Color(uiColor: .systemGray),
                                stroke: Color.clear,
                                textColor: .white,
                                showsStroke: false
                            )
                        }
                    }

                    Text(option.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(paywallSecondaryTextColor)

                    if !option.priceText.isEmpty {
                        Text(option.priceText)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(paywallPrimaryTextColor)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(accent)
                } else {
                    Image(systemName: "circle")
                        .font(.title3)
                        .foregroundStyle(paywallSecondaryTextColor.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isSelected
                            ? accent.opacity(colorScheme == .dark ? 0.2 : 0.16)
                            : paywallCardFillColor
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? accent : paywallCardStrokeColor,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .opacity(option.isAvailable ? 1.0 : 0.85)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isPurchasingPlan)
    }

    private func paywallAccent(for planID: String) -> Color {
        switch planID {
        case PurchaseManager.weeklyProductID:
            return Color(red: 0.27, green: 0.52, blue: 0.98)
        case PurchaseManager.monthlyProductID:
            return Color(red: 0.62, green: 0.38, blue: 0.96)
        case PurchaseManager.lifetimeProductID:
            return Color(red: 0.96, green: 0.56, blue: 0.22)
        default:
            return Color(red: 0.40, green: 0.48, blue: 0.72)
        }
    }

    private func paywallBadge(for planID: String) -> String? {
        switch planID {
        case PurchaseManager.monthlyProductID:
            return L10n.tr("Most popular")
        case PurchaseManager.lifetimeProductID:
            return L10n.tr("Best value")
        default:
            return nil
        }
    }

    private func paywallBadgeChip(
        title: String,
        fill: Color,
        stroke: Color,
        textColor: Color,
        showsStroke: Bool
    ) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .foregroundStyle(textColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(fill)
            )
            .overlay(
                Capsule()
                    .stroke(stroke, lineWidth: showsStroke ? 1 : 0)
            )
            .fixedSize(horizontal: true, vertical: false)
    }

    private var paywallBackgroundGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.11, green: 0.12, blue: 0.22),
                Color(red: 0.11, green: 0.17, blue: 0.33)
            ]
        }
        return [
            Color(red: 0.96, green: 0.98, blue: 1.0),
            Color(red: 0.90, green: 0.94, blue: 1.0)
        ]
    }

    private var paywallPrimaryTextColor: Color {
        colorScheme == .dark ? .white : Color(uiColor: .label)
    }

    private var paywallSecondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.82) : Color(uiColor: .secondaryLabel)
    }

    private var paywallTertiaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.68) : Color(uiColor: .tertiaryLabel)
    }

    private var paywallCardFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.8)
    }

    private var paywallCardStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.12)
    }

    private var paywallRestoreFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.88)
    }

    private var paywallRestoreStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.12)
    }

    private var paywallCTAStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.24) : Color.black.opacity(0.1)
    }

    private var paywallCTAShadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.28) : .black.opacity(0.14)
    }

    private var cancelConversionAccent: Color {
        Color(uiColor: .systemRed)
    }

    private var cancelConversionTextColor: Color {
        colorScheme == .dark ? .white : Color(uiColor: .label)
    }

    private var cancelConversionFill: LinearGradient {
        LinearGradient(
            colors: [
                Color(uiColor: .systemRed).opacity(colorScheme == .dark ? 0.34 : 0.13),
                Color(uiColor: .systemOrange).opacity(colorScheme == .dark ? 0.26 : 0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cancelConversionStroke: Color {
        Color(uiColor: .systemRed).opacity(colorScheme == .dark ? 0.55 : 0.30)
    }

    private var cancelConversionShadow: Color {
        Color(uiColor: .systemRed).opacity(colorScheme == .dark ? 0.20 : 0.12)
    }

    private var pageBackground: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    private var heroGradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color.indigo.opacity(0.72),
                Color.teal.opacity(0.62)
            ]
        }
        return [
            Color.blue.opacity(0.75),
            Color.cyan.opacity(0.65)
        ]
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(uiColor: .secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.38 : 0.18), lineWidth: 1)
            )
    }

    private var confirmationActionLabel: String {
        guard let pendingStepNavigation else { return L10n.tr("Go back") }
        switch pendingStepNavigation {
        case .source:
            return L10n.tr("Go to Step 1 and reset video")
        case .settings:
            return L10n.tr("Go to Step 2")
        case .conversion:
            return L10n.tr("Go to Step 3")
        }
    }

    private var confirmationMessage: String {
        guard let pendingStepNavigation else { return "" }
        switch pendingStepNavigation {
        case .source:
            return L10n.tr("This will clear the selected source video and current conversion results.")
        case .settings:
            return L10n.tr("You will return to settings for this video.")
        case .conversion:
            return L10n.tr("You will return to conversion.")
        }
    }

    private func canNavigateToStep(_ step: VideoCompressionViewModel.WorkflowStep) -> Bool {
        guard !viewModel.isConverting else { return false }
        return step.rawValue < viewModel.workflowStep.rawValue
    }

    private func requestStepNavigation(to step: VideoCompressionViewModel.WorkflowStep) {
        guard canNavigateToStep(step) else { return }
        pendingStepNavigation = step
    }

    private func navigateToPendingStep() {
        guard let pendingStepNavigation else { return }
        defer { self.pendingStepNavigation = nil }

        switch pendingStepNavigation {
        case .source:
            viewModel.startNewConversionFlow()
        case .settings:
            viewModel.returnToSettingsStep()
        case .conversion:
            break
        }
    }

    private func presentShowcaseDoneSheetIfNeeded() {
        guard Self.showcaseStepArgument == "done" else { return }
        guard viewModel.hasConversionSucceeded else { return }
        guard !hasPresentedShowcaseDoneSheet else { return }
        hasPresentedShowcaseDoneSheet = true
        isSaveDestinationDialogPresented = true
    }

    private var showcaseSettingsVariant: SettingsShowcaseVariant? {
        guard Self.showcaseStepArgument == "settings" else { return nil }
        return Self.showcaseVariantArgument
    }

    private func applySettingsShowcaseVariantIfNeeded() {
        guard !didConfigureShowcaseSettingsVariant else { return }
        didConfigureShowcaseSettingsVariant = true
        guard let showcaseSettingsVariant else { return }

        isAdvancedSettingsExpanded = true
        viewModel.allowResizeUpTo10x = true

        if showcaseSettingsVariant == .advancedBottom {
            shouldScrollToSettingsBottom = true
        }
    }

    private func scrollToShowcaseSettingsBottomIfNeeded(_ proxy: ScrollViewProxy) {
        guard shouldScrollToSettingsBottom else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(nil) {
                proxy.scrollTo(Self.settingsBottomAnchorID, anchor: .bottom)
            }
        }
    }
}

private struct SaveDestinationSheet: View {
    let onSaveToGallery: () -> Void
    let onSaveToFiles: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("Save converted video"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                Text(L10n.tr("Choose where to save your result."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 2)
            .padding(.horizontal, 2)

            VStack(spacing: 10) {
                saveOptionButton(
                    title: L10n.tr("Save to Gallery"),
                    subtitle: L10n.tr("Add directly to Photos"),
                    icon: "photo.stack.fill",
                    iconGradient: [Color.blue, Color.cyan]
                ) {
                    dismiss()
                    onSaveToGallery()
                }

                saveOptionButton(
                    title: L10n.tr("Save to Files"),
                    subtitle: L10n.tr("Choose folder in Files app"),
                    icon: "folder.fill",
                    iconGradient: [Color.orange, Color.yellow]
                ) {
                    dismiss()
                    onSaveToFiles()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemBackground))
    }

    private var primaryTextColor: Color {
        Color(uiColor: .label)
    }

    private func saveOptionButton(
        title: String,
        subtitle: String,
        icon: String,
        iconGradient: [Color],
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: iconGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(primaryTextColor)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(colorScheme == .dark ? 0.4 : 0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PremiumCTAPrimaryShimmer: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isInitialState = true

    let cornerRadius: CGFloat

    private var min: CGFloat { -0.28 }
    private var max: CGFloat { 1.28 }

    private var shimmerStartPoint: UnitPoint {
        if layoutDirection == .rightToLeft {
            return isInitialState ? UnitPoint(x: max, y: min) : UnitPoint(x: 0, y: 1)
        }
        return isInitialState ? UnitPoint(x: min, y: min) : UnitPoint(x: 1, y: 1)
    }

    private var shimmerEndPoint: UnitPoint {
        if layoutDirection == .rightToLeft {
            return isInitialState ? UnitPoint(x: 1, y: 0) : UnitPoint(x: min, y: max)
        }
        return isInitialState ? UnitPoint(x: 0, y: 0) : UnitPoint(x: max, y: max)
    }

    private var highlightColor: Color {
        colorScheme == .dark ? .white.opacity(0.26) : .white.opacity(0.58)
    }

    var body: some View {
        LinearGradient(
            colors: [.clear, highlightColor, .clear],
            startPoint: shimmerStartPoint,
            endPoint: shimmerEndPoint
        )
        .blendMode(.screen)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .compositingGroup()
        .opacity(reduceMotion ? 0 : 1)
        .animation(
            .linear(duration: 2.2)
                .delay(0.25)
                .repeatForever(autoreverses: false),
            value: isInitialState
        )
        .onAppear {
            guard !reduceMotion else { return }
            DispatchQueue.main.async {
                isInitialState = false
            }
        }
        .onChange(of: reduceMotion) { _, newValue in
            if newValue {
                isInitialState = true
                return
            }
            DispatchQueue.main.async {
                isInitialState = false
            }
        }
    }
}

private struct PremiumCTASecondaryShimmer: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -0.4

    let cornerRadius: CGFloat

    private var highlightColor: Color {
        colorScheme == .dark ? .white.opacity(0.18) : .white.opacity(0.32)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let shimmerWidth = max(width * 0.24, 58)
            let travel = width + shimmerWidth * 2

            LinearGradient(
                colors: [.clear, highlightColor, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: shimmerWidth, height: height * 1.7)
            .rotationEffect(.degrees(18))
            .offset(x: (phase * travel) - shimmerWidth)
            .onAppear {
                guard !reduceMotion else { return }
                phase = -0.4
                withAnimation(
                    .linear(duration: 2.4)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1.4
                }
            }
            .onChange(of: reduceMotion) { _, newValue in
                if newValue {
                    phase = -0.4
                    return
                }
                phase = -0.4
                withAnimation(
                    .linear(duration: 2.4)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1.4
                }
            }
            .onDisappear {
                phase = -0.4
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .opacity(reduceMotion ? 0 : 1)
        .allowsHitTesting(false)
    }
}

private struct FilesExportPicker: UIViewControllerRepresentable {
    let url: URL
    let onComplete: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onComplete: (Result<URL, Error>) -> Void
        private var hasFinished = false

        init(onComplete: @escaping (Result<URL, Error>) -> Void) {
            self.onComplete = onComplete
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !hasFinished else { return }
            hasFinished = true
            guard let url = urls.first else {
                onComplete(.failure(CocoaError(.fileNoSuchFile)))
                return
            }
            onComplete(.success(url))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard !hasFinished else { return }
            hasFinished = true
            onComplete(.failure(CocoaError(.userCancelled)))
        }
    }
}

#if DEBUG
private struct DebugShakeDetector: UIViewControllerRepresentable {
    let onShake: () -> Void

    func makeUIViewController(context: Context) -> DebugShakeViewController {
        let controller = DebugShakeViewController()
        controller.onShake = onShake
        return controller
    }

    func updateUIViewController(_ uiViewController: DebugShakeViewController, context: Context) {
        uiViewController.onShake = onShake
    }
}

private final class DebugShakeViewController: UIViewController {
    var onShake: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        resignFirstResponder()
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }
        onShake?()
    }
}
#endif
