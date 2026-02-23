import AVKit
import Combine
import Foundation
import StoreKit
import SwiftUI
import os

@MainActor
final class AppViewModel: ObservableObject {
    // MARK: - Published State

    @Published var promptText: String = "" {
        didSet {
            if promptText.count > promptCharacterLimit {
                promptText = String(promptText.prefix(promptCharacterLimit))
            }
        }
    }
    @Published var isDemoModeActive: Bool = false
    @Published var isAuthenticated: Bool = false
    @Published var isSubscribed: Bool = false
    @Published var isSubscribing: Bool = false
    @Published var isRestoringPurchases: Bool = false
    @Published var isPaywallPresented: Bool = false
    @Published var isSignInSheetPresented: Bool = false
    @Published var isGenerationOverlayVisible: Bool = false
    @Published var phase: ViewPhase = .idle
    @Published var currentStageIndex: Int = 0
    @Published var downloadPhase: DownloadPhase = .idle
    @Published var isGoogleLinking: Bool = false
    @Published var isAppleLinking: Bool = false
    @Published var isReviewLinking: Bool = false
    @Published var connectedAccountEmail: String?
    @Published var connectedAccountProvider: AuthProvider = .guest
    @Published var projectSummaries: [ProjectSummary] = []
    @Published var isLoadingProjects: Bool = false
    @Published var player: AVPlayer?
    @Published var isProjectSheetPresented: Bool = false
    @Published var isSettingsPresented: Bool = false {
        didSet {
            if oldValue == false && isSettingsPresented {
                refreshSubscriptionStatusFromAppStore()
            }
        }
    }
    @Published var tokenBalance: Int?
    @Published var isLoadingTokenBalance: Bool = false
    @Published var authErrorMessage: String?
    @Published var isSigningOut: Bool = false
    @Published var isDeletingAccount: Bool = false
    @Published var accountDeletionSuccessMessage: String?
    @Published var accountDeletionErrorMessage: String?
    @Published var selectedProjectDetail: ProjectDetail?
    @Published var isProjectDetailPresented: Bool = false
    @Published var isLoadingProjectDetail: Bool = false
    @Published var projectDetailError: String?
    @Published var projectDetailPlayer: AVPlayer?
    @Published var projectDetailPlayerStatus: PlayerStatus = .idle
    @Published var projectDetailDownloadPhase: DownloadPhase = .idle
    @Published var downloadProgress: DownloadProgress?
    @Published var isProjectSubmissionInFlight: Bool = false
    @Published var projectCreationErrorMessage: String?
    @Published var voiceOptions: [VoiceOption] = []
    @Published var isLoadingVoices: Bool = false
    @Published var voiceLoadErrorMessage: String?
    @Published var selectedVoiceId: String?
    @Published var targetLanguageCodes: [String] = [TargetLanguage.default.rawValue]
    @Published var selectedDurationSeconds: Int = DurationOption.default.rawValue
    @Published var characterOptionsGlobal: [CharacterOption] = []
    @Published var characterOptionsUser: [CharacterOption] = []
    @Published var isLoadingCharacters: Bool = false
    @Published var characterLoadErrorMessage: String?
    @Published var selectedCharacterSelection: StoredCharacterSelection = .dynamic
    @Published var projectSettings: ProjectCreationSettings = .default
    @Published var isProjectSettingsLoading: Bool = false
    @Published var templateOptions: [TemplateOption] = []
    @Published var isLoadingTemplates: Bool = false
    @Published var templateLoadErrorMessage: String?
    @Published var selectedTemplateId: String?
    @Published var subscriptionProducts: [PaywallPlan: Product] = [:]
    @Published var isSubscriptionProductLoading: Bool = false
    @Published var subscriptionStatus: SubscriptionStatusResponse?
    var activeGenerationProjectId: String?
    var transactionUpdatesTask: Task<Void, Never>?
    var subscriptionStatusTask: Task<Void, Never>?
    @Published var isGuestUpgradeBannerVisible: Bool = false

    // MARK: - Private State

    var generationTask: Task<Void, Never>?
    let stages: [ProcessingStage] = [
        ProcessingStage(iconName: "wand.and.stars", titleKey: "status_story", iconTint: Color(red: 0.93, green: 0.42, blue: 0.07), backgroundTint: Color(red: 1.0, green: 0.9, blue: 0.75)),
        ProcessingStage(iconName: "mic.fill", titleKey: "status_voiceover", iconTint: Color(red: 0.96, green: 0.65, blue: 0.16), backgroundTint: Color(red: 1.0, green: 0.93, blue: 0.82)),
        ProcessingStage(iconName: "captions.bubble.fill", titleKey: "status_captions", iconTint: Color(red: 0.15, green: 0.65, blue: 0.89), backgroundTint: Color(red: 0.82, green: 0.95, blue: 1.0)),
        ProcessingStage(iconName: "photo.on.rectangle.angled", titleKey: "status_visuals", iconTint: Color(red: 0.41, green: 0.58, blue: 0.98), backgroundTint: Color(red: 0.84, green: 0.9, blue: 1.0)),
        ProcessingStage(iconName: "scissors", titleKey: "status_splicing", iconTint: Color(red: 0.93, green: 0.42, blue: 0.07), backgroundTint: Color(red: 1.0, green: 0.9, blue: 0.75)),
        ProcessingStage(iconName: "film.stack", titleKey: "status_final_cut", iconTint: Color(red: 0.39, green: 0.76, blue: 0.31), backgroundTint: Color(red: 0.88, green: 0.97, blue: 0.84))
    ]

    let demoPromptKey = "demo_prompt_sample"

    func localizedDemoPrompt(for locale: Locale?) -> String {
        if let identifier = locale?.identifier,
           let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return NSLocalizedString(demoPromptKey, bundle: bundle, comment: "")
        }
        return NSLocalizedString(demoPromptKey, comment: "")
    }

    func isDemoPromptText(_ text: String, locale: Locale?) -> Bool {
        if text == localizedDemoPrompt(for: locale) {
            return true
        }
        return text == localizedDemoPrompt(for: nil)
    }
    let stageDuration: UInt64 = 3_000_000_000
    let promptCharacterLimit = 10_000
    let minimumPromptLength = 6
    var activeMode: GenerationMode = .production
    let remoteVideoURL = URL(string: "https://static.awesomeapp.com/api/media/video/2025/11/e1d2f451-18d2-4b49-9968-2438a504a623.mp4")!
    let defaultVoiceName = "Finn"
    let defaultVoiceIdHint = "7a9a5bfd-a29d-46e1-a097-3d5408c63651"
    let defaultVoiceExternalIdHint = "vBKc2FfBKJfcZNyEt1n6"
    let refreshTokenRenewalLeadTime: TimeInterval = 60 * 60 * 24 * 30
    private var isProjectFetchInFlight = false
    private var projectDetailTask: Task<Void, Never>?
    private var projectPollingTasks: [String: Task<Void, Never>] = [:]
    var templateDefaultId: String?
    var paywallContext: PaywallContext = .manual
    var pendingGenerationRequest: Bool = false
    @Published var selectedProjectDetailLanguage: String?

    // MARK: - Dependencies

    let authStore = AuthSessionStore()
    let subscriptionStore = SubscriptionStatusStore()
    let apiClient = MobileAPIClient()
    let logger = Logger(subsystem: "com.awesomeapp.mobile", category: "Auth")
    let voiceCacheStore = VoiceOptionCacheStore()
    let templateCacheStore = TemplateOptionCacheStore()
    let projectPreferencesStore = ProjectCreationPreferencesStore()
    let appleSignInCoordinator = AppleSignInCoordinator()
    var voiceLoadingTask: Task<Void, Never>?
    var projectSettingsTask: Task<Void, Never>?
    var templateLoadingTask: Task<Void, Never>?
    var templateImagePrefetchTask: Task<Void, Never>?
    private var projectDetailPlayerObservation: NSKeyValueObservation?
    var currentSession: AuthSession? {
        didSet {
            applySessionSideEffects()
        }
    }
    var guestSignInTask: Task<AuthSession?, Never>?

    // MARK: - Init

    init() {
        isSubscribed = false
        loadLanguagePreferences()
        loadDurationPreference()
        loadCharacterSelectionPreference()
        loadCachedProjectSettings()
        loadCachedVoiceOptions()
        refreshVoiceOptions(force: false)
        loadCachedTemplateOptions()
        loadTemplatePreference()
        refreshTemplateOptions(force: false)

        if let savedSession = authStore.load() {
            currentSession = savedSession
            applySessionSideEffects()
            let email = savedSession.user.email
            logger.log("Auth redrift: loaded stored session for \(email, privacy: .public)")
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refreshTokenBalanceIfNeeded(force: true)
                await self.restorePreviousSessionIfNeeded(force: true)
                await self.ensureGuestSessionIfNeeded(force: true)
                self.refreshProjectSummaries(force: true)
                self.refreshProjectSettings(force: true)
            }
        } else {
            logger.log("Auth redrift: no stored session found, triggering silent restore")
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.restorePreviousSessionIfNeeded(force: true)
                await self.ensureGuestSessionIfNeeded(force: true)
                await self.refreshTokenBalanceIfNeeded(force: true)
                self.refreshProjectSummaries(force: true)
                self.refreshProjectSettings(force: true)
            }
        }

        startTransactionUpdatesListener()
    }

    deinit {
        voiceLoadingTask?.cancel()
        projectSettingsTask?.cancel()
        templateLoadingTask?.cancel()
        templateImagePrefetchTask?.cancel()
        transactionUpdatesTask?.cancel()
        subscriptionStatusTask?.cancel()
        guestSignInTask?.cancel()
        Task { @MainActor [weak self] in
            self?.stopAllStatusPolling()
        }
    }

    func refreshProjectSummaries(force: Bool = false) {
        if isProjectFetchInFlight && !force { return }
        guard currentSession != nil else {
            projectSummaries = []
            return
        }
        isProjectFetchInFlight = true
        isLoadingProjects = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.isProjectFetchInFlight = false
                    self.isLoadingProjects = false
                }
            }
            do {
                let session = try await self.ensureValidSession()
                let remote = try await self.apiClient.fetchProjects(accessToken: session.tokens.accessToken)
                let summaries = remote.map { ProjectSummary(response: $0) }
                await MainActor.run {
                    self.projectSummaries = summaries
                    self.scheduleStatusPolling(for: summaries)
                    if var detail = self.selectedProjectDetail,
                       let updated = summaries.first(where: { $0.id == detail.id }) {
                        detail.merge(summary: updated)
                        self.selectedProjectDetail = detail
                    }
                }
            } catch MobileAPIError.notSignedIn, MobileAPIError.unauthorized {
                await MainActor.run {
                    self.projectSummaries = []
                    self.selectedProjectDetail = nil
                }
            } catch {
                self.logger.error("Auth redrift: failed to refresh projects - \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func openProjectDetail(_ summary: ProjectSummary) {
        resetProjectDetailMedia()
        selectedProjectDetail = ProjectDetail(summary: summary)
        selectedProjectDetailLanguage = nil
        projectDetailError = nil
        isProjectDetailPresented = true
        startPollingProjectStatus(for: summary.id)
        loadProjectDetail(for: summary.id, force: true)
    }

    func reloadSelectedProjectDetail() {
        guard let id = selectedProjectDetail?.id else { return }
        loadProjectDetail(for: id, force: true)
    }

    func dismissProjectDetail() {
        projectDetailTask?.cancel()
        projectDetailTask = nil
        isProjectDetailPresented = false
        projectDetailError = nil
        selectedProjectDetail = nil
        selectedProjectDetailLanguage = nil
        resetProjectDetailMedia()
    }

    private func loadProjectDetail(for projectId: String, force: Bool = false) {
        if isLoadingProjectDetail && !force { return }
        guard currentSession != nil else { return }
        isLoadingProjectDetail = true
        projectDetailError = nil
        projectDetailTask?.cancel()
        projectDetailTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.isLoadingProjectDetail = false
                }
            }
            do {
                let session = try await self.ensureValidSession()
                let response = try await self.apiClient.fetchProjectDetail(id: projectId, accessToken: session.tokens.accessToken)
                let detail = self.decorateProjectDetail(ProjectDetail(response: response))
                await MainActor.run {
                    self.selectedProjectDetail = detail
                    self.applyDefaultProjectLanguageIfNeeded(detail: detail)
                    self.prepareProjectDetailMedia(for: detail)
                }
            } catch {
                await MainActor.run {
                    self.projectDetailError = error.localizedDescription
                }
            }
        }
    }

    func downloadSelectedProjectVideo() async {
        guard let url = selectedProjectDetail?.finalVideoURL(for: selectedProjectDetailLanguage) else { return }
        downloadProgress = nil
        await downloadVideo(sourcePlayer: projectDetailPlayer, fallbackURL: url, phaseKeyPath: \AppViewModel.projectDetailDownloadPhase)
    }

    func downloadAllProjectVideos() async {
        guard let detail = selectedProjectDetail else { return }
        let downloadable = detail.languageVariants.compactMap { variant -> (String, URL)? in
            guard let url = variant.finalVideoURL else { return nil }
            return (variant.languageCode, url)
        }
        guard !downloadable.isEmpty else { return }

        var anySuccess = false
        var lastError: String?

        for (index, pair) in downloadable.enumerated() {
            let (code, url) = pair
            downloadProgress = DownloadProgress(current: index + 1, total: downloadable.count, mode: .all)
            await downloadVideo(sourcePlayer: nil, fallbackURL: url, phaseKeyPath: \AppViewModel.projectDetailDownloadPhase)

            switch projectDetailDownloadPhase {
            case .success:
                anySuccess = true
            case .failed(let message):
                lastError = message
                logger.error("Download failed for language \(code): \(message, privacy: .public)")
            default:
                break
            }
        }

        downloadProgress = nil

        if anySuccess {
            projectDetailDownloadPhase = .success
        } else if let lastError {
            projectDetailDownloadPhase = .failed(message: lastError)
        } else {
            projectDetailDownloadPhase = .failed(message: NSLocalizedString("error_video_missing", comment: ""))
        }
    }

    func selectProjectDetailLanguage(_ code: String) {
        guard let detail = selectedProjectDetail else { return }
        guard detail.languages.contains(code) else { return }
        guard detail.status.isComplete, detail.languages.count > 1 else { return }
        selectedProjectDetailLanguage = code
        prepareProjectDetailMedia(for: detail)
    }

    func scheduleStatusPolling(for summaries: [ProjectSummary]) {
        // Polling across all projects has been disabled to reduce load.
    }

    func startPollingProjectStatus(for projectId: String) {
        guard projectPollingTasks[projectId] == nil else { return }
        projectPollingTasks[projectId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.projectPollingTasks.removeValue(forKey: projectId)
                }
            }
            while !Task.isCancelled {
                do {
                    let session = try await self.ensureValidSession()
                    let detail = try await self.apiClient.fetchProjectDetail(id: projectId, accessToken: session.tokens.accessToken)
                    await MainActor.run {
                        self.applyProjectDetailUpdate(detail)
                    }
                    let status = AppViewModel.ProjectSummaryStatus(rawValue: detail.status) ?? .unknown
                    if status.isTerminal { break }
                } catch MobileAPIError.notSignedIn, MobileAPIError.unauthorized {
                    break
                } catch {
                    self.logger.error("Auth redrift: project poll failed for \(projectId, privacy: .public) - \(error.localizedDescription, privacy: .public)")
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    func stopPollingProjectStatus(for projectId: String) {
        projectPollingTasks[projectId]?.cancel()
        projectPollingTasks.removeValue(forKey: projectId)
    }

    func stopAllStatusPolling() {
        for task in projectPollingTasks.values {
            task.cancel()
        }
        projectPollingTasks.removeAll()
    }

    func applyProjectDetailUpdate(_ response: ProjectDetailResponse) {
        let status = AppViewModel.ProjectSummaryStatus(rawValue: response.status) ?? .unknown
        let summary = ProjectSummary(id: response.id, title: response.title, createdAt: response.createdAt, status: status)
        replaceProjectSummary(with: summary)
        let isActiveProject = activeGenerationProjectId == response.id
        let shouldAutoPresentResult = isActiveProject && isGenerationOverlayVisible
        if selectedProjectDetail?.id == response.id {
            let detail = decorateProjectDetail(ProjectDetail(response: response))
            selectedProjectDetail = detail
            applyDefaultProjectLanguageIfNeeded(detail: detail)
            prepareProjectDetailMedia(for: detail)
        }
        if isActiveProject {
            currentStageIndex = max(0, min(stages.count - 1, status.progressIndex(in: stages)))
            if status.isTerminal {
                finalizeGenerationOverlayIfNeeded()
                if shouldAutoPresentResult {
                    presentCompletedProjectDetailIfNeeded(summary: summary, detailResponse: response)
                }
            }
        }
        if status.isTerminal {
            stopPollingProjectStatus(for: response.id)
            if isActiveProject {
                activeGenerationProjectId = nil
            }
        }
    }

    func replaceProjectSummary(with summary: ProjectSummary) {
        var updated = projectSummaries
        if let index = updated.firstIndex(where: { $0.id == summary.id }) {
            updated[index] = summary
        } else {
            updated.insert(summary, at: 0)
        }
        projectSummaries = updated
    }

    private func finalizeGenerationOverlayIfNeeded() {
        isProjectSubmissionInFlight = false
        currentStageIndex = stages.count - 1
        phase = .idle
        isGenerationOverlayVisible = false
        activeGenerationProjectId = nil
    }

    private func presentCompletedProjectDetailIfNeeded(summary: ProjectSummary, detailResponse: ProjectDetailResponse) {
        if isProjectDetailPresented, selectedProjectDetail?.id != summary.id {
            return
        }
        if !isProjectSheetPresented {
            isProjectSheetPresented = true
        }
        resetProjectDetailMedia()
        let detail = decorateProjectDetail(ProjectDetail(response: detailResponse))
        selectedProjectDetail = detail
        applyDefaultProjectLanguageIfNeeded(detail: detail)
        prepareProjectDetailMedia(for: detail)
        projectDetailError = nil
        isProjectDetailPresented = true
    }

    private func prepareProjectDetailMedia(for detail: ProjectDetail) {
        let desiredLanguage = selectedProjectDetailLanguage
        let resolvedURL = detail.finalVideoURL(for: desiredLanguage)

        guard let url = resolvedURL else {
            projectDetailPlayer?.pause()
            projectDetailPlayer = nil
            projectDetailDownloadPhase = .idle
            return
        }

        // Stop any current playback before swapping the player to avoid overlapping audio.
        projectDetailPlayer?.pause()

        if let asset = projectDetailPlayer?.currentItem?.asset as? AVURLAsset,
           asset.url == url {
            projectDetailDownloadPhase = .ready
            if projectDetailPlayerStatus != .ready {
                projectDetailPlayerStatus = .ready
            }
            return
        }

        projectDetailPlayerObservation?.invalidate()
        projectDetailPlayerStatus = .loading

        let item = AVPlayerItem(url: url)
        projectDetailPlayerObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.projectDetailPlayerStatus = .ready
                case .failed:
                    self.projectDetailPlayerStatus = .failed(item.error?.localizedDescription)
                default:
                    break
                }
            }
        }

        projectDetailPlayer = AVPlayer(playerItem: item)
        projectDetailDownloadPhase = .ready
    }

    private func resetProjectDetailMedia() {
        projectDetailPlayer?.pause()
        projectDetailPlayerObservation?.invalidate()
        projectDetailPlayerObservation = nil
        projectDetailPlayer = nil
        projectDetailDownloadPhase = .idle
        projectDetailPlayerStatus = .idle
    }

    private func decorateProjectDetail(_ detail: ProjectDetail) -> ProjectDetail {
        var enriched = detail
        enriched.voiceTitle = resolveVoiceTitle(for: detail.voiceExternalId)
        return enriched
    }

    func resolveVoiceTitle(for externalId: String?) -> String? {
        guard let externalId else { return nil }
        return voiceOptions.first(where: { $0.externalId == externalId || $0.id == externalId })?.title
    }

    private func applyDefaultProjectLanguageIfNeeded(detail: ProjectDetail) {
        guard !detail.languages.isEmpty else {
            selectedProjectDetailLanguage = nil
            return
        }
        if let selectedLanguage = selectedProjectDetailLanguage, detail.languages.contains(selectedLanguage) {
            return
        }
        selectedProjectDetailLanguage = detail.languages.first
    }

    func updateGenerationPollingState() {
        guard let projectId = activeGenerationProjectId else {
            return
        }
        if isGenerationOverlayVisible {
            startPollingProjectStatus(for: projectId)
        } else {
            stopPollingProjectStatus(for: projectId)
        }
    }

    private func applySessionSideEffects() {
        isAuthenticated = currentSession != nil
        let provider = currentSession?.provider ?? .guest
        connectedAccountProvider = provider
        connectedAccountEmail = provider == .guest ? nil : currentSession?.user.email
        if let userId = currentSession?.user.id {
            isSubscribed = subscriptionStore.loadStatus(for: userId)
        } else {
            isSubscribed = false
        }
        refreshSubscriptionStatusFromAppStore()
    }

    func showGuestUpgradeBannerIfNeeded() {
        guard currentSession?.provider == .guest else { return }
        if !isGuestUpgradeBannerVisible {
            withAnimation {
                isGuestUpgradeBannerVisible = true
            }
        }
    }

    func dismissGuestUpgradeBanner() {
        if isGuestUpgradeBannerVisible {
            withAnimation {
                isGuestUpgradeBannerVisible = false
            }
        }
    }

    func openGuestUpgradeSettings() {
        dismissGuestUpgradeBanner()
        isSettingsPresented = true
    }
}
