import Foundation

struct ProjectCreationSettings: Codable, Equatable {
    var includeDefaultMusic: Bool
    var addOverlay: Bool
    var includeCallToAction: Bool
    var autoApproveScript: Bool
    var autoApproveAudio: Bool
    var watermarkEnabled: Bool
    var captionsEnabled: Bool
    var scriptCreationGuidanceEnabled: Bool
    var scriptCreationGuidance: String
    var audioStyleGuidanceEnabled: Bool
    var audioStyleGuidance: String
    var defaultUseScript: Bool

    static let `default` = ProjectCreationSettings(
        includeDefaultMusic: true,
        addOverlay: true,
        includeCallToAction: true,
        autoApproveScript: true,
        autoApproveAudio: true,
        watermarkEnabled: true,
        captionsEnabled: true,
        scriptCreationGuidanceEnabled: false,
        scriptCreationGuidance: "",
        audioStyleGuidanceEnabled: false,
        audioStyleGuidance: "",
        defaultUseScript: false
    )
}

extension ProjectCreationSettings {
    init(response: UserSettingsResponse) {
        self.includeDefaultMusic = response.includeDefaultMusic
        self.addOverlay = response.addOverlay
        self.includeCallToAction = response.includeCallToAction
        self.autoApproveScript = response.autoApproveScript
        self.autoApproveAudio = response.autoApproveAudio
        self.watermarkEnabled = response.watermarkEnabled
        self.captionsEnabled = response.captionsEnabled
        self.scriptCreationGuidanceEnabled = response.scriptCreationGuidanceEnabled
        self.scriptCreationGuidance = response.scriptCreationGuidance
        self.audioStyleGuidanceEnabled = response.audioStyleGuidanceEnabled
        self.audioStyleGuidance = response.audioStyleGuidance
        self.defaultUseScript = response.defaultUseScript
    }
}

extension ProjectCreationSettings {
    private enum CodingKeys: String, CodingKey {
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ProjectCreationSettings.default
        includeDefaultMusic = try container.decodeIfPresent(Bool.self, forKey: .includeDefaultMusic) ?? defaults.includeDefaultMusic
        addOverlay = try container.decodeIfPresent(Bool.self, forKey: .addOverlay) ?? defaults.addOverlay
        includeCallToAction = try container.decodeIfPresent(Bool.self, forKey: .includeCallToAction) ?? defaults.includeCallToAction
        autoApproveScript = try container.decodeIfPresent(Bool.self, forKey: .autoApproveScript) ?? defaults.autoApproveScript
        autoApproveAudio = try container.decodeIfPresent(Bool.self, forKey: .autoApproveAudio) ?? defaults.autoApproveAudio
        watermarkEnabled = try container.decodeIfPresent(Bool.self, forKey: .watermarkEnabled) ?? defaults.watermarkEnabled
        captionsEnabled = try container.decodeIfPresent(Bool.self, forKey: .captionsEnabled) ?? defaults.captionsEnabled
        scriptCreationGuidanceEnabled = try container.decodeIfPresent(Bool.self, forKey: .scriptCreationGuidanceEnabled) ?? defaults.scriptCreationGuidanceEnabled
        scriptCreationGuidance = try container.decodeIfPresent(String.self, forKey: .scriptCreationGuidance) ?? defaults.scriptCreationGuidance
        audioStyleGuidanceEnabled = try container.decodeIfPresent(Bool.self, forKey: .audioStyleGuidanceEnabled) ?? defaults.audioStyleGuidanceEnabled
        audioStyleGuidance = try container.decodeIfPresent(String.self, forKey: .audioStyleGuidance) ?? defaults.audioStyleGuidance
        defaultUseScript = try container.decodeIfPresent(Bool.self, forKey: .defaultUseScript) ?? defaults.defaultUseScript
    }
}
