import Foundation

extension AppViewModel {
    var currentVoiceTitle: String {
        voiceOption(withId: selectedVoiceId)?.title ?? defaultVoiceName
    }

    var isUsingDefaultVoice: Bool {
        guard let selectedVoiceId else { return true }
        return selectedVoiceId == (resolvedDefaultVoiceId ?? defaultVoiceIdHint)
    }

    var resolvedDefaultVoiceId: String? {
        if voiceOptions.contains(where: { $0.id == defaultVoiceIdHint }) {
            return defaultVoiceIdHint
        }
        return voiceOptions.first(where: { $0.externalId == defaultVoiceExternalIdHint })?.id
    }

    func loadCachedVoiceOptions() {
        if let cached = voiceCacheStore.load() {
            voiceOptions = cached.voices
            refreshSelectedProjectDetailVoiceMetadata()
        }
        if let storedSelection = projectPreferencesStore.value(for: .selectedVoiceId) {
            selectedVoiceId = storedSelection
        }
        ensureVoiceSelectionConsistency()
    }

    func refreshVoiceOptions(force: Bool = false) {
        if isLoadingVoices && !force { return }
        voiceLoadingTask?.cancel()
        voiceLoadingTask = Task { [weak self] in
            await self?.performVoiceRefresh()
            await MainActor.run {
                self?.voiceLoadingTask = nil
            }
        }
    }

    func retryVoiceLoad() {
        refreshVoiceOptions(force: true)
    }

    func selectVoice(withId id: String) {
        guard selectedVoiceId != id else { return }
        selectedVoiceId = id
        projectPreferencesStore.set(id, for: .selectedVoiceId)
    }

    func selectVoice(_ option: VoiceOption) {
        selectVoice(withId: option.id)
    }

    func voiceOption(withId id: String?) -> VoiceOption? {
        guard let id else { return nil }
        return voiceOptions.first(where: { $0.id == id })
    }

    func refreshSelectedProjectDetailVoiceMetadata() {
        guard var detail = selectedProjectDetail else { return }
        detail.voiceTitle = resolveVoiceTitle(for: detail.voiceExternalId)
        selectedProjectDetail = detail
    }

    private func performVoiceRefresh() async {
        isLoadingVoices = true
        voiceLoadErrorMessage = nil
        do {
            let responses = try await apiClient.fetchVoiceOptions()
            let options = responses.map(VoiceOption.init)
            voiceOptions = options
            voiceCacheStore.save(voices: options)
            refreshSelectedProjectDetailVoiceMetadata()
            ensureVoiceSelectionConsistency()
            isLoadingVoices = false
        } catch {
            voiceLoadErrorMessage = error.localizedDescription
            isLoadingVoices = false
        }
    }

    private func ensureVoiceSelectionConsistency() {
        if let current = selectedVoiceId,
           voiceOptions.contains(where: { $0.id == current }) {
            projectPreferencesStore.set(current, for: .selectedVoiceId)
            return
        }

        if let stored = projectPreferencesStore.value(for: .selectedVoiceId),
           voiceOptions.contains(where: { $0.id == stored }) {
            selectedVoiceId = stored
            return
        }

        if let defaultId = resolvedDefaultVoiceId,
           voiceOptions.contains(where: { $0.id == defaultId }) {
            selectedVoiceId = defaultId
            projectPreferencesStore.set(defaultId, for: .selectedVoiceId)
            return
        }

        guard let first = voiceOptions.first else {
            selectedVoiceId = nil
            projectPreferencesStore.set(nil, for: .selectedVoiceId)
            return
        }

        selectedVoiceId = first.id
        projectPreferencesStore.set(first.id, for: .selectedVoiceId)
    }

    private func voiceExternalId(forVoiceId id: String?) -> String? {
        guard let id,
              let option = voiceOption(withId: id),
              let externalId = option.externalId,
              !externalId.isEmpty else {
            return nil
        }
        return externalId
    }

    func resolvedVoiceExternalIdForSubmission() -> String? {
        if let selected = voiceExternalId(forVoiceId: selectedVoiceId) {
            return selected
        }
        if let fallbackDefault = voiceExternalId(forVoiceId: resolvedDefaultVoiceId ?? defaultVoiceIdHint) {
            return fallbackDefault
        }
        if let fallback = voiceOptions.first(where: { ($0.externalId ?? "").isEmpty == false })?.externalId {
            return fallback
        }
        return defaultVoiceExternalIdHint
    }
}
