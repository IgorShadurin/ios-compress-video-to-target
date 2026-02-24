import Foundation

final class CompressionSettingsStore {
    private let defaults: UserDefaults
    private let key = "compress_video_settings_v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CompressionSettings? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        return try? JSONDecoder().decode(CompressionSettings.self, from: data)
    }

    func save(_ settings: CompressionSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
