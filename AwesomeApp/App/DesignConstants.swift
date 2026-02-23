import CoreGraphics
import SwiftUI

enum UIRadius {
    static let input: CGFloat = 16
    static let card: CGFloat = 20
    static let control: CGFloat = 18
    static let tile: CGFloat = 16
    static let chip: CGFloat = 12
}

enum UIStrokeColor {
    static var light: Color { Color.black.opacity(0.18) }
    static var dark: Color { Color.white.opacity(0.28) }
}
