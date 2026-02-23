import Foundation

struct TemplateOption: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let description: String?
    let previewImageUrl: String?
    let previewVideoUrl: String?
    let voiceTitle: String?
    let captionsTitle: String?
    let overlayTitle: String?
    let artStyleTitle: String?
    let weight: Int?

    init(
        id: String,
        title: String,
        description: String?,
        previewImageUrl: String?,
        previewVideoUrl: String?,
        voiceTitle: String?,
        captionsTitle: String?,
        overlayTitle: String?,
        artStyleTitle: String?,
        weight: Int?
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.previewImageUrl = previewImageUrl
        self.previewVideoUrl = previewVideoUrl
        self.voiceTitle = voiceTitle
        self.captionsTitle = captionsTitle
        self.overlayTitle = overlayTitle
        self.artStyleTitle = artStyleTitle
        self.weight = weight
    }

    init(response: TemplateOptionResponse) {
        self.init(
            id: response.id,
            title: response.title,
            description: response.description,
            previewImageUrl: response.previewImageUrl,
            previewVideoUrl: response.previewVideoUrl,
            voiceTitle: response.voice?.title,
            captionsTitle: response.captionsStyle?.title,
            overlayTitle: response.overlay?.title,
            artStyleTitle: response.artStyle?.title,
            weight: response.weight
        )
    }

    var previewImageURL: URL? {
        resolvedURL(from: previewImageUrl)
    }

    var previewVideoURL: URL? {
        resolvedURL(from: previewVideoUrl)
    }

    var metadataSummary: String? {
        var parts: [String] = []
        if let voiceTitle, !voiceTitle.isEmpty { parts.append(voiceTitle) }
        if let overlayTitle, !overlayTitle.isEmpty { parts.append(overlayTitle) }
        if let captionsTitle, !captionsTitle.isEmpty { parts.append(captionsTitle) }
        if let artStyleTitle, !artStyleTitle.isEmpty { parts.append(artStyleTitle) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " • ")
    }
    private func resolvedURL(from value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if let absolute = URL(string: value), absolute.scheme != nil {
            return absolute
        }
        if value.hasPrefix("/") {
            return URL(string: value, relativeTo: AppConfiguration.apiBaseURL)?.absoluteURL
        }
        return AppConfiguration.apiBaseURL.appendingPathComponent(value).absoluteURL
    }
}
