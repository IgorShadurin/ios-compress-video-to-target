import Foundation

enum TargetLanguage: String, CaseIterable, Identifiable, Codable {
    case en
    case ru
    case es
    case fr
    case de
    case pt
    case it

    static let `default`: TargetLanguage = .en

    var id: String { rawValue }

    var label: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        case .es: return "Español"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .pt: return "Português"
        case .it: return "Italiano"
        }
    }

    var flag: String {
        switch self {
        case .en: return "🇺🇸"
        case .ru: return "🇷🇺"
        case .es: return "🇪🇸"
        case .fr: return "🇫🇷"
        case .de: return "🇩🇪"
        case .pt: return "🇵🇹"
        case .it: return "🇮🇹"
        }
    }

    static func normalizeSelection(_ codes: [String]?) -> [String] {
        let allowed = Set(codes?.map { $0.lowercased() } ?? [])
        var normalized: [String] = []
        for language in TargetLanguage.allCases {
            if allowed.contains(language.rawValue) {
                normalized.append(language.rawValue)
            }
        }
        if normalized.isEmpty {
            normalized = [TargetLanguage.default.rawValue]
        }
        return normalized
    }

    static func summary(for codes: [String]) -> String {
        let normalized = normalizeSelection(codes)
        if normalized.count == TargetLanguage.allCases.count {
            return NSLocalizedString("language_summary_all", comment: "All languages summary")
        }
        guard let first = normalized.first,
              let firstLang = TargetLanguage(rawValue: first) else {
            return TargetLanguage.default.label
        }
        if normalized.count == 1 {
            return firstLang.label
        }
        return "\(firstLang.label) +\(normalized.count - 1)"
    }
}
