import CoreGraphics
import Foundation

public enum VideoGeometry {
    public static func usesQuarterTurnTransform(
        _ transform: CGAffineTransform,
        tolerance: CGFloat = 0.001
    ) -> Bool {
        abs(transform.a) <= tolerance &&
            abs(transform.d) <= tolerance &&
            abs(abs(transform.b) - 1) <= tolerance &&
            abs(abs(transform.c) - 1) <= tolerance
    }

    public static func writerBaseDimensions(
        displayWidth: Int,
        displayHeight: Int,
        preferredTransform: CGAffineTransform
    ) -> (width: Int, height: Int) {
        let clampedDisplayWidth = max(1, displayWidth)
        let clampedDisplayHeight = max(1, displayHeight)

        // For rotated portrait tracks (natural landscape + 90/270 transform), writer settings
        // must use encoded (natural) dimensions. Otherwise output orientation becomes wrong.
        if usesQuarterTurnTransform(preferredTransform) {
            return (width: clampedDisplayHeight, height: clampedDisplayWidth)
        }

        return (width: clampedDisplayWidth, height: clampedDisplayHeight)
    }
}
