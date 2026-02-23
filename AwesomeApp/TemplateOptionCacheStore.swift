import Foundation

struct CachedTemplateOptions: Codable {
    let updatedAt: Date
    let options: [TemplateOption]
}

final class TemplateOptionCacheStore {
    private let defaults: UserDefaults
    private let cacheKey = "com.awesomeapp.template-options"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> CachedTemplateOptions? {
        guard let data = defaults.data(forKey: cacheKey) else { return nil }
        return try? decoder.decode(CachedTemplateOptions.self, from: data)
    }

    func save(options: [TemplateOption]) {
        let payload = CachedTemplateOptions(updatedAt: Date(), options: options)
        guard let data = try? encoder.encode(payload) else { return }
        defaults.set(data, forKey: cacheKey)
    }
}
