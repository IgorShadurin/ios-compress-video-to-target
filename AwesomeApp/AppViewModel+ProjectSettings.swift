import Foundation
import os

extension AppViewModel {
    enum ProjectSettingKey: String {
        case includeDefaultMusic
        case addOverlay
        case includeCallToAction
        case autoApproveScript
        case autoApproveAudio
        case watermarkEnabled
        case captionsEnabled
        case scriptCreationGuidanceEnabled
        case scriptCreationGuidance
        case audioStyleGuidanceEnabled
        case audioStyleGuidance
        case defaultUseScript
    }

    var projectSettingsIndicatorActive: Bool {
        projectSettings != .default
    }

    func loadCachedProjectSettings() {
        if let stored = projectPreferencesStore.value(for: .projectSettings) {
            projectSettings = stored
        } else {
            projectSettings = .default
        }
        enforceAutoApprovalDefaults()
    }

    func refreshProjectSettings(force: Bool = false) {
        if isProjectSettingsLoading && !force { return }
        guard currentSession != nil else { return }
        projectSettingsTask?.cancel()
        isProjectSettingsLoading = true
        projectSettingsTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.isProjectSettingsLoading = false
                    self.projectSettingsTask = nil
                }
            }
            do {
                let session = try await self.ensureValidSession()
                let response = try await self.apiClient.fetchUserSettings(accessToken: session.tokens.accessToken)
                await MainActor.run {
                    self.applyProjectSettingsResponse(response)
                }
            } catch {
                self.logger.error("Project settings refresh failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func applyProjectSettingsResponse(_ response: UserSettingsResponse) {
        let settings = ProjectCreationSettings(response: response)
        projectSettings = settings
        projectPreferencesStore.set(settings, for: .projectSettings)
        enforceAutoApprovalDefaults()
    }

    func setIncludeDefaultMusic(_ value: Bool) {
        updateProjectSettings(keyPath: \ProjectCreationSettings.includeDefaultMusic, value: value, key: .includeDefaultMusic)
    }

    func setAddOverlay(_ value: Bool) {
        updateProjectSettings(keyPath: \ProjectCreationSettings.addOverlay, value: value, key: .addOverlay)
    }

    func setIncludeCallToAction(_ value: Bool) {
        updateProjectSettings(keyPath: \ProjectCreationSettings.includeCallToAction, value: value, key: .includeCallToAction)
    }

    func setAutoApproveScript(_ value: Bool) {
        updateProjectSettings(keyPath: \ProjectCreationSettings.autoApproveScript, value: value, key: .autoApproveScript)
    }

    func setAutoApproveAudio(_ value: Bool) {
        updateProjectSettings(keyPath: \ProjectCreationSettings.autoApproveAudio, value: value, key: .autoApproveAudio)
    }

    func setWatermarkEnabled(_ value: Bool) {
        updateProjectSettings(keyPath: \ProjectCreationSettings.watermarkEnabled, value: value, key: .watermarkEnabled)
    }

    func setCaptionsEnabled(_ value: Bool) {
        updateProjectSettings(keyPath: \ProjectCreationSettings.captionsEnabled, value: value, key: .captionsEnabled)
    }

    func setScriptCreationGuidanceEnabled(_ value: Bool) {
        updateProjectSettings(keyPath: \ProjectCreationSettings.scriptCreationGuidanceEnabled, value: value, key: .scriptCreationGuidanceEnabled)
    }

    func setScriptCreationGuidance(_ value: String) {
        let sanitized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        updateProjectSettings(keyPath: \ProjectCreationSettings.scriptCreationGuidance, value: sanitized, key: .scriptCreationGuidance)
    }

    func setAudioStyleGuidanceEnabled(_ value: Bool) {
        updateProjectSettings(keyPath: \ProjectCreationSettings.audioStyleGuidanceEnabled, value: value, key: .audioStyleGuidanceEnabled)
    }

    func setAudioStyleGuidance(_ value: String) {
        let sanitized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        updateProjectSettings(keyPath: \ProjectCreationSettings.audioStyleGuidance, value: sanitized, key: .audioStyleGuidance)
    }

    func setDefaultUseScript(_ value: Bool) {
        updateProjectSettings(keyPath: \ProjectCreationSettings.defaultUseScript, value: value, key: .defaultUseScript)
    }

    private func updateProjectSettings<Value: Equatable & Encodable>(
        keyPath: WritableKeyPath<ProjectCreationSettings, Value>,
        value: Value,
        key: ProjectSettingKey
    ) {
        if projectSettings[keyPath: keyPath] == value { return }
        projectSettings[keyPath: keyPath] = value
        projectPreferencesStore.set(projectSettings, for: .projectSettings)
        sendProjectSettingPatch(key: key.rawValue, value: value)
    }

    private func sendProjectSettingPatch<Value: Encodable>(key: String, value: Value) {
        guard currentSession != nil else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let session = try await self.ensureValidSession()
                _ = try await self.apiClient.updateUserSetting(key: key, value: value, accessToken: session.tokens.accessToken)
            } catch {
                self.logger.error("Failed to update project setting \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func enforceAutoApprovalDefaults() {
        var didUpdate = false
        if !projectSettings.autoApproveScript {
            projectSettings.autoApproveScript = true
            didUpdate = true
            sendProjectSettingPatch(key: ProjectSettingKey.autoApproveScript.rawValue, value: true)
        }
        if !projectSettings.autoApproveAudio {
            projectSettings.autoApproveAudio = true
            didUpdate = true
            sendProjectSettingPatch(key: ProjectSettingKey.autoApproveAudio.rawValue, value: true)
        }
        if didUpdate {
            projectPreferencesStore.set(projectSettings, for: .projectSettings)
        }
    }
}
