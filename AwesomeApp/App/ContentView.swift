import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = VideoCompressionViewModel()
    @State private var isAdvancedSettingsExpanded = false
    @State private var isFileImporterPresented = false
    @State private var pendingStepNavigation: VideoCompressionViewModel.WorkflowStep?
    @Environment(\.colorScheme) private var colorScheme

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
            .navigationTitle("Compress")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: viewModel.pickerItem) { _, _ in
            Task {
                await viewModel.handlePickerChange()
            }
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
            "Leave current step?",
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
            Button("Cancel", role: .cancel) {
                pendingStepNavigation = nil
            }
        } message: {
            Text(confirmationMessage)
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
                    .disabled(!canNavigateToStep(step))
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
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: heroGradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 168)

                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Select Source Video")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Choose from your gallery or Files.")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    .padding(16)
                }

                PhotosPicker(
                    selection: $viewModel.pickerItem,
                    matching: .videos,
                    preferredItemEncoding: .current,
                    photoLibrary: .shared()
                ) {
                    Label("Choose from Gallery", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("Choose from Files", systemImage: "folder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)

                Text("Processed locally on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                quotaStatusCard

                if !viewModel.hasPremiumAccess {
                    Button {
                        viewModel.presentPaywall()
                    } label: {
                        Label("Upgrade to Unlimited", systemImage: "crown.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
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
        ScrollView {
            VStack(spacing: 12) {
                sourceCompactCard
                quotaStatusCard

                if !viewModel.hasPremiumAccess {
                    Button {
                        viewModel.presentPaywall()
                    } label: {
                        Label("Upgrade to Unlimited", systemImage: "crown.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.isLoadingSourceDetails {
                    loadingCard
                }

                if viewModel.sourceMetadata != nil {
                    targetSettingsCard

                    Button {
                        Task {
                            await viewModel.convert()
                        }
                    } label: {
                        Label("Start Conversion", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canConvert)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color(uiColor: .systemRed))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    viewModel.startNewConversionFlow()
                } label: {
                    Label("Choose another source", systemImage: "photo.badge.plus")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 16)
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
                Text("Source Preview")
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
            Text("Loading video details...")
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
            Text("Target Settings")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("Target size", text: $viewModel.targetValueText)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                Picker("Unit", selection: $viewModel.targetUnit) {
                    ForEach(CompressionUnit.allCases, id: \.self) { unit in
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

            Picker("Target format", selection: $viewModel.selectedOutputFormatID) {
                ForEach(viewModel.formatOptions, id: \.self) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .pickerStyle(.menu)

            DisclosureGroup("Advanced options", isExpanded: $isAdvancedSettingsExpanded) {
                Toggle("Adjust resolution", isOn: $viewModel.allowResizeUpTo10x)

                if viewModel.allowResizeUpTo10x {
                    Picker("Output resolution", selection: $viewModel.selectedResolutionScale) {
                        ForEach(viewModel.resolutionOptions, id: \.id) { option in
                            Text(option.title).tag(option.scale)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Toggle("Remove HDR", isOn: $viewModel.removeHDR)
            }

            if viewModel.isLoadingOutputFormats {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking format compatibility...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let validationMessage = viewModel.validationMessage {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(Color(uiColor: .systemRed))
            }

            Text("Compression cannot exceed 30x reduction from source size.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(cardBackground)
    }

    private var conversionStep: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 10) {
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
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Color(uiColor: .systemGreen))
                    }

                    Text(viewModel.isConverting ? "Converting video..." : "Conversion complete")
                        .font(.headline)

                    if viewModel.isConverting {
                        Text("Please do not close the app until conversion finishes.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button(role: .destructive) {
                            viewModel.cancelConversion()
                        } label: {
                            Label(
                                viewModel.isCancellingConversion ? "Cancelling..." : "Cancel conversion",
                                systemImage: "xmark.circle"
                            )
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.canCancelConversion)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(cardBackground)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Estimation")
                        .font(.headline)

                    if let targetSizeText = viewModel.targetSizeText {
                        LabeledContent("Target size") {
                            Text(targetSizeText)
                        }
                    }

                    if let estimatedOutputText = viewModel.estimatedOutputText {
                        LabeledContent("Estimated first pass") {
                            Text(estimatedOutputText)
                        }
                    }

                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(cardBackground)

                if let outputSizeText = viewModel.outputSizeText {
                    VStack(spacing: 10) {
                        LabeledContent("Output size") {
                            Text(outputSizeText)
                        }

                        Button {
                            Task {
                                await viewModel.saveToPhotoLibrary()
                            }
                        } label: {
                            Label("Save to Gallery", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canSaveResult)
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

                if !viewModel.isConverting {
                    Button {
                        viewModel.returnToSettingsStep()
                    } label: {
                        Label("Adjust target settings", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        viewModel.startNewConversionFlow()
                    } label: {
                        Label("Start with another source", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private var quotaStatusCard: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.hasPremiumAccess ? "checkmark.seal.fill" : "lock.open")
                .foregroundStyle(viewModel.hasPremiumAccess ? Color(uiColor: .systemGreen) : .secondary)
            Text(viewModel.quotaStatusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var paywallSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Unlock Unlimited Conversions")
                        .font(.title3.weight(.bold))

                    Text("Free plan allows only 1 video conversion per day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if viewModel.purchaseOptions.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(viewModel.purchaseOptions) { option in
                            Button {
                                Task {
                                    await viewModel.purchasePlan(planID: option.id)
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "creditcard")
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.title)
                                            .font(.headline)
                                        Text(option.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(option.priceText)
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!option.isAvailable || viewModel.isPurchasingPlan)
                        }
                    }

                    Button {
                        Task {
                            await viewModel.restorePurchases()
                        }
                    } label: {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isPurchasingPlan)

                    Button {
                        viewModel.dismissPaywall()
                    } label: {
                        Label("Continue with Free Plan", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color(uiColor: .systemRed))
                    }
                }
                .padding(16)
            }
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        viewModel.dismissPaywall()
                    }
                }
            }
        }
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
        guard let pendingStepNavigation else { return "Go back" }
        switch pendingStepNavigation {
        case .source:
            return "Go to Step 1 and reset video"
        case .settings:
            return "Go to Step 2"
        case .conversion:
            return "Go to Step 3"
        }
    }

    private var confirmationMessage: String {
        guard let pendingStepNavigation else { return "" }
        switch pendingStepNavigation {
        case .source:
            return "This will clear the selected source video and current conversion results."
        case .settings:
            return "You will return to settings for this video."
        case .conversion:
            return "You will return to conversion."
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
}
