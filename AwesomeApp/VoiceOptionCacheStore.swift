import Foundation

struct CachedVoiceOptions: Codable {
    let updatedAt: Date
    let voices: [VoiceOption]
}

final class VoiceOptionCacheStore {
    private let defaults: UserDefaults
    private let cacheKey = "com.awesomeapp.voice-options"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> CachedVoiceOptions? {
        guard let data = defaults.data(forKey: cacheKey) else { return nil }
        return try? decoder.decode(CachedVoiceOptions.self, from: data)
    }

    func save(voices: [VoiceOption]) {
        let payload = CachedVoiceOptions(updatedAt: Date(), voices: voices)
        guard let data = try? encoder.encode(payload) else { return }
        defaults.set(data, forKey: cacheKey)
    }
}

struct ProjectPreferenceKey<Value: Codable> {
    let rawValue: String
    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

final class ProjectCreationPreferencesStore {
    private let defaults: UserDefaults
    private let storageKey = "com.awesomeapp.project-preferences"
    private var cache: [String: String] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    struct StoredPreferences: Codable {
        var entries: [String: String]
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let stored = try? decoder.decode(StoredPreferences.self, from: data) {
            cache = stored.entries
        }
    }

    func value<T: Codable>(for key: ProjectPreferenceKey<T>) -> T? {
        guard let json = cache[key.rawValue],
              let data = json.data(using: .utf8),
              let decoded = try? decoder.decode(T.self, from: data) else {
            return nil
        }
        return decoded
    }

    func set<T: Codable>(_ value: T?, for key: ProjectPreferenceKey<T>) {
        if let value {
            guard let data = try? encoder.encode(value),
                  let string = String(data: data, encoding: .utf8) else { return }
            cache[key.rawValue] = string
        } else {
            cache.removeValue(forKey: key.rawValue)
        }
        persist()
    }

    private func persist() {
        let payload = StoredPreferences(entries: cache)
        guard let data = try? encoder.encode(payload) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

extension ProjectPreferenceKey where Value == String {
    static let selectedVoiceId = ProjectPreferenceKey<String>("selectedVoiceId")
    static let selectedTemplateId = ProjectPreferenceKey<String>("selectedTemplateId")
}

extension ProjectPreferenceKey where Value == [String] {
    static let selectedLanguages = ProjectPreferenceKey<[String]>("selectedLanguages")
}

extension ProjectPreferenceKey where Value == StoredCharacterSelection {
    static let selectedCharacter = ProjectPreferenceKey<StoredCharacterSelection>("selectedCharacter")
}

extension ProjectPreferenceKey where Value == Int {
    static let selectedDurationSeconds = ProjectPreferenceKey<Int>("selectedDurationSeconds")
}

extension ProjectPreferenceKey where Value == ProjectCreationSettings {
    static let projectSettings = ProjectPreferenceKey<ProjectCreationSettings>("projectSettings")
}
