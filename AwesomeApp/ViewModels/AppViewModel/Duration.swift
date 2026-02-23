import Foundation

extension AppViewModel {
    var durationAccessibilityValue: String {
        DurationOption(rawValue: selectedDurationSeconds)?.spokenLabel ?? DurationOption.default.spokenLabel
    }

    var isUsingDefaultDuration: Bool {
        selectedDurationSeconds == DurationOption.default.rawValue
    }

    func loadDurationPreference() {
        if let stored = projectPreferencesStore.value(for: .selectedDurationSeconds),
           DurationOption(rawValue: stored) != nil {
            selectedDurationSeconds = stored
        } else {
            selectedDurationSeconds = DurationOption.default.rawValue
        }
    }

    func selectDuration(_ option: DurationOption) {
        guard selectedDurationSeconds != option.rawValue else { return }
        selectedDurationSeconds = option.rawValue
        projectPreferencesStore.set(option.rawValue, for: .selectedDurationSeconds)
    }
}
