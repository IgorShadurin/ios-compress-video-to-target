import Foundation

enum DurationOption: Int, CaseIterable, Identifiable, Codable {
    case seconds30 = 30
    case seconds60 = 60
    case seconds90 = 90
    case seconds120 = 120

    static let `default`: DurationOption = .seconds30

    var id: Int { rawValue }

    var shortLabel: String {
        let minutes = rawValue / 60
        let seconds = rawValue % 60
        if minutes == 0 {
            return "\(seconds)s"
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var spokenLabel: String {
        let minutes = rawValue / 60
        let seconds = rawValue % 60
        if minutes > 0 && seconds > 0 {
            return String(
                format: NSLocalizedString("duration_accessibility_minutes_seconds_format", comment: "minutes and seconds"),
                minutes,
                seconds
            )
        } else if minutes > 0 {
            return String(
                format: NSLocalizedString("duration_accessibility_minutes_format", comment: "whole minutes"),
                minutes
            )
        } else {
            return String(
                format: NSLocalizedString("duration_accessibility_seconds_format", comment: "seconds"),
                seconds
            )
        }
    }
}
