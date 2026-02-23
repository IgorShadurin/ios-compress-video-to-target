import AVKit
import Foundation
import Photos
import SwiftUI

extension AppViewModel {
    // MARK: - Prompt & Generation Flow

    func beginDemoPrompt(locale: Locale) {
        guard phase != .processing else { return }
        promptText = localizedDemoPrompt(for: locale)
        isDemoModeActive = true
    }

    func cancelDemoPrompt(locale: Locale) {
        guard phase != .processing else { return }
        if isDemoPromptText(promptText, locale: locale) {
            promptText = ""
        }
        isDemoModeActive = false
    }

    func startGeneration() {
        guard hasMinimumPromptContent else { return }
        guard canStartGenerationWithoutPaywall else {
            return
        }
        guard !isProjectSubmissionInFlight else { return }

        activeMode = isDemoModeActive ? .demo : .production
        projectCreationErrorMessage = nil
        isProjectSubmissionInFlight = true
        isGenerationOverlayVisible = true
        updateGenerationPollingState()
        downloadPhase = .idle
        phase = .processing
        currentStageIndex = 0
        player?.pause()
        player = nil

        generationTask?.cancel()
        generationTask = Task { [weak self] in
            guard let self else { return }
            if self.activeMode == .demo {
                await self.runDemoGenerationFlow()
            } else {
                await self.submitProject()
            }
        }
    }

    func handleCreateButtonTap() {
        if isDemoModeActive {
            startGeneration()
            return
        }
        guard hasMinimumPromptContent else { return }
        if !isAuthenticated {
            pendingGenerationRequest = true
            presentSignInSheet()
            return
        }
        if !hasPaidGenerationAccess {
            pendingGenerationRequest = true
            presentPaywall(force: true, context: .creationRequest)
            return
        }
        startGeneration()
    }

    func resumePendingGenerationFlowIfNeeded() {
        guard pendingGenerationRequest else { return }
        guard isAuthenticated else { return }
        if hasPaidGenerationAccess {
            pendingGenerationRequest = false
            startGeneration()
            return
        }
        presentPaywall(force: false, context: .creationRequest)
    }

    func resetResult() {
        guard phase == .result else { return }
        player?.pause()
        player = nil
        phase = .idle
        downloadPhase = .idle
        if let projectId = activeGenerationProjectId {
            stopPollingProjectStatus(for: projectId)
        }
        player?.pause()
        player = nil
        activeGenerationProjectId = nil
        isGenerationOverlayVisible = false
    }

    func dismissGenerationOverlay() {
        if activeMode == .demo, phase == .processing {
            cancelActiveDemoGeneration()
            return
        }
        if let projectId = activeGenerationProjectId {
            stopPollingProjectStatus(for: projectId)
        }
        stopResultPlayback()
        activeGenerationProjectId = nil
        isGenerationOverlayVisible = false
    }

    func downloadResultVideo() async {
        guard case .result = phase else { return }
        await downloadVideo(sourcePlayer: player, fallbackURL: remoteVideoURL, phaseKeyPath: \AppViewModel.downloadPhase)
    }

    private func submitProject() async {
        do {
            let summary = try await createProjectWithDefaults()
            await MainActor.run {
                self.prependProjectSummary(summary)
                self.refreshProjectSummaries(force: true)
                self.promptText = ""
                self.activeGenerationProjectId = summary.id
                self.updateGenerationPollingState()
            }
        } catch {
            await MainActor.run {
                self.projectCreationErrorMessage = self.describeProjectCreationError(error)
                self.phase = .idle
                self.downloadPhase = .idle
                self.isGenerationOverlayVisible = false
                self.activeGenerationProjectId = nil
                self.currentStageIndex = 0
            }
        }

        await MainActor.run {
            self.isProjectSubmissionInFlight = false
            self.generationTask = nil
        }
    }

    private func runDemoGenerationFlow() async {
        let stageDelay = stageDuration
        defer {
            Task { @MainActor in
                self.isProjectSubmissionInFlight = false
                self.generationTask = nil
            }
        }

        do {
            for index in 0..<stages.count {
                if index > 0 {
                    try await Task.sleep(nanoseconds: stageDelay)
                }
                try Task.checkCancellation()
                await MainActor.run {
                    self.currentStageIndex = index
                }
            }

            try await Task.sleep(nanoseconds: stageDelay)
            try Task.checkCancellation()

            await MainActor.run {
                self.promptText = ""
                self.finalizeGeneration()
            }
        } catch is CancellationError {
            return
        } catch {
            await MainActor.run {
                self.projectCreationErrorMessage = error.localizedDescription
            }
        }
    }

    private func cancelActiveDemoGeneration() {
        guard activeMode == .demo else { return }
        generationTask?.cancel()
        generationTask = nil
        phase = .idle
        downloadPhase = .idle
        currentStageIndex = 0
        stopResultPlayback()
        isProjectSubmissionInFlight = false
        isGenerationOverlayVisible = false
        activeGenerationProjectId = nil
    }

    private func stopResultPlayback() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    private func createProjectWithDefaults() async throws -> ProjectListItemResponse {
        let session = try await ensureValidSession()
        let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let useExactScript = projectSettings.defaultUseScript
        let durationValue = useExactScript ? nil : selectedDurationSeconds
        let request = CreateProjectRequest(
            prompt: trimmedPrompt.isEmpty ? "Untitled project" : trimmedPrompt,
            durationSeconds: durationValue,
            characterSelection: buildCharacterSelectionPayload(),
            useExactTextAsScript: useExactScript,
            voiceId: resolvedVoiceExternalIdForSubmission(),
            templateId: selectedTemplateId,
            languages: targetLanguageCodes
        )
        return try await apiClient.createProject(request: request, accessToken: session.tokens.accessToken)
    }

    private func prependProjectSummary(_ response: ProjectListItemResponse) {
        let summary = ProjectSummary(response: response)
        var updated = projectSummaries.filter { $0.id != summary.id }
        updated.insert(summary, at: 0)
        projectSummaries = updated
    }

    private func describeProjectCreationError(_ error: Error) -> String {
        if let apiError = error as? MobileAPIError {
            switch apiError {
            case .server(let message):
                return message
            case .unauthorized, .notSignedIn:
                return NSLocalizedString("error_generic", comment: "")
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private func buildCharacterSelectionPayload() -> CreateProjectRequest.CharacterSelection? {
        let selection = selectedCharacterSelection
        switch selection.source {
        case .dynamic:
            return CreateProjectRequest.CharacterSelection(
                source: "dynamic",
                characterId: nil,
                userCharacterId: nil,
                variationId: nil
            )
        case .global:
            guard let variationId = selection.variationId else { return nil }
            return CreateProjectRequest.CharacterSelection(
                source: nil,
                characterId: selection.characterId,
                userCharacterId: nil,
                variationId: variationId
            )
        case .user:
            guard let variationId = selection.variationId else { return nil }
            return CreateProjectRequest.CharacterSelection(
                source: nil,
                characterId: nil,
                userCharacterId: selection.userCharacterId,
                variationId: variationId
            )
        }
    }

    // MARK: - Derived Values

    var promptCharacterCount: Int { promptText.count }

    var promptLimit: Int { promptCharacterLimit }

    var hasMinimumPromptContent: Bool { trimmedPromptCount >= minimumPromptLength }

    var canShowCreateButton: Bool {
        if isProjectSubmissionInFlight { return false }
        return hasMinimumPromptContent
    }

    var hasPaidGenerationAccess: Bool {
        isSubscribed || (tokenBalance ?? 0) > 0
    }

    var shouldShowDemoModeButton: Bool {
        // Show "Try it for free" only for guests to avoid flicker for logged-in users.
        !isAuthenticated
    }

    var modeLabelKey: LocalizedStringKey {
        (isDemoModeActive ? GenerationMode.demo : GenerationMode.production) == .demo
        ? LocalizedStringKey("mode_demo") : LocalizedStringKey("mode_production")
    }

    // MARK: - Private Helpers

    private func finalizeGeneration() {
        phase = .result
        player = AVPlayer(url: remoteVideoURL)
        downloadPhase = .ready
        if isGenerationOverlayVisible {
            player?.play()
        }
    }

    func downloadVideo(
        sourcePlayer: AVPlayer?,
        fallbackURL: URL?,
        phaseKeyPath: ReferenceWritableKeyPath<AppViewModel, DownloadPhase>
    ) async {
        if case .downloading = self[keyPath: phaseKeyPath] {
            return
        }

        guard let sourceURL = (sourcePlayer?.currentItem?.asset as? AVURLAsset)?.url ?? fallbackURL else {
            self[keyPath: phaseKeyPath] = .failed(message: NSLocalizedString("error_video_missing", comment: ""))
            return
        }

        self[keyPath: phaseKeyPath] = .downloading

        if downloadProgress == nil {
            downloadProgress = DownloadProgress(current: 1, total: 1, mode: .single)
        }

        do {
            let localURL = try await fetchVideo(from: sourceURL)
            try await ensurePhotoAccess()
            try await saveVideoToLibrary(fileURL: localURL)
            self[keyPath: phaseKeyPath] = .success
        } catch {
            self[keyPath: phaseKeyPath] = .failed(message: error.localizedDescription)
        }

        if case .single = downloadProgress?.mode {
            downloadProgress = nil
        }
    }

    private func fetchVideo(from url: URL) async throws -> URL {
        let (downloadedURL, _) = try await URLSession.shared.download(from: url)
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: downloadedURL, to: destination)
        return destination
    }

    private func ensurePhotoAccess() async throws {
        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { authorization in
                continuation.resume(returning: authorization)
            }
        }

        switch status {
        case .authorized, .limited:
            return
        case .denied, .restricted, .notDetermined:
            throw PhotoPermissionError.denied
        @unknown default:
            throw PhotoPermissionError.denied
        }
    }

    private func saveVideoToLibrary(fileURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }, completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: PhotoPermissionError.unknown)
                }
            })
        }
    }

    private var trimmedPromptCount: Int {
        promptText.trimmingCharacters(in: .whitespacesAndNewlines).count
    }
}
