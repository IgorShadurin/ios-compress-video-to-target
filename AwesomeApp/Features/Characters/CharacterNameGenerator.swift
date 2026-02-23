import Foundation

enum CharacterNameGenerator {
    private static let colors: [String] = [
        "Amber", "Amethyst", "Aqua", "Azure", "Beige", "Black", "Blue", "Bronze",
        "Brown", "Burgundy", "Cerulean", "Charcoal", "Chartreuse", "Cobalt", "Coral",
        "Crimson", "Cyan", "Emerald", "Fuchsia", "Gold", "Goldenrod", "Gray", "Green",
        "Indigo", "Ivory", "Jade", "Lavender", "Lilac", "Lime", "Magenta", "Maroon",
        "Mint", "Mustard", "Navy", "Olive", "Orange", "Peach", "Periwinkle", "Pink",
        "Platinum", "Plum", "Purple", "Red", "Rose", "Ruby", "Saffron", "Silver", "Teal",
        "Turquoise", "Violet", "White", "Yellow"
    ]

    private static let animals: [String] = [
        "Albatross", "Alligator", "Antelope", "Armadillo", "Badger", "Barracuda", "Beaver",
        "Bison", "Bobcat", "Buffalo", "Butterfly", "Camel", "Caribou", "Cheetah",
        "Chameleon", "Cobra", "Cougar", "Coyote", "Crane", "Crocodile", "Dolphin",
        "Dragonfly", "Eagle", "Falcon", "Ferret", "Fox", "Gazelle", "Giraffe", "Gorilla",
        "Hedgehog", "Heron", "Jaguar", "Kangaroo", "Koala", "Leopard", "Lynx", "Manatee",
        "Mongoose", "Moose", "Narwhal", "Octopus", "Otter", "Panda", "Panther", "Penguin",
        "Quokka", "Raccoon", "Seal", "Tiger", "Wolf"
    ]

    static func generate() -> String {
        let color = colors.randomElement() ?? "Azure"
        let animal = animals.randomElement() ?? "Otter"
        let number = String(format: "%04d", Int.random(in: 0..<10_000))
        return "\(color) \(animal) \(number)"
    }
}
