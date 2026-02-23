import Foundation

enum CharacterSelectionSource: String, Codable {
    case dynamic
    case global
    case user
}

struct StoredCharacterSelection: Codable, Equatable {
    var source: CharacterSelectionSource
    var characterId: String?
    var userCharacterId: String?
    var variationId: String?

    static let dynamic = StoredCharacterSelection(source: .dynamic, characterId: nil, userCharacterId: nil, variationId: nil)
}

struct CharacterOption: Identifiable, Hashable {
    enum Status {
        case ready
        case processing
        case failed
    }

    let id: String
    let source: CharacterSelectionSource
    let characterId: String?
    let userCharacterId: String?
    let variationId: String?
    let title: String
    let description: String?
    let imageURL: URL?
    let status: Status

    var selection: StoredCharacterSelection {
        StoredCharacterSelection(
            source: source,
            characterId: characterId,
            userCharacterId: userCharacterId,
            variationId: variationId
        )
    }

    var isSelectable: Bool {
        source == .dynamic || status == .ready
    }
}
