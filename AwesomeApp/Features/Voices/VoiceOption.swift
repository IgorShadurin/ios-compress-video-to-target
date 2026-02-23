import Foundation

struct VoiceOption: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let description: String?
    let externalId: String?
    let languages: [String]
    let speed: String?
    let gender: String?
    let previewURL: URL?

    init(
        id: String,
        title: String,
        description: String?,
        externalId: String?,
        languages: [String]?,
        speed: String?,
        gender: String?,
        previewURL: URL?
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.externalId = externalId
        self.languages = languages ?? []
        self.speed = speed
        self.gender = gender
        self.previewURL = previewURL
    }

    init(response: VoiceOptionResponse) {
        self.init(
            id: response.id,
            title: response.title,
            description: response.description,
            externalId: response.externalId,
            languages: response.languages,
            speed: response.speed,
            gender: response.gender,
            previewURL: VoiceOption.makeAbsolutePreviewURL(from: response.previewPath)
        )
    }

    var hasPreview: Bool { previewURL != nil }

    var metadataSummary: String? {
        let languageCode = languages.first?.uppercased()
        let pieces = [languageCode, formattedGender, formattedSpeed].compactMap { $0 }
        guard !pieces.isEmpty else { return nil }
        return pieces.joined(separator: " · ")
    }

    private var formattedGender: String? {
        guard let gender, !gender.isEmpty else { return nil }
        return gender.capitalized
    }

    private var formattedSpeed: String? {
        guard let speed, !speed.isEmpty else { return nil }
        return speed.capitalized
    }
}

private extension VoiceOption {
    static func makeAbsolutePreviewURL(from path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        return URL(string: path, relativeTo: AppConfiguration.apiBaseURL)?.absoluteURL
    }
}
