import Foundation

extension AppViewModel {
    var languageSummaryText: String {
        TargetLanguage.summary(for: targetLanguageCodes)
    }

    var isUsingDefaultLanguages: Bool {
        targetLanguageCodes == [TargetLanguage.default.rawValue]
    }

    var hasAllLanguagesSelected: Bool {
        Set(targetLanguageCodes) == Set(TargetLanguage.allCases.map(\.rawValue))
    }

    var canRemoveEnglishFromSelection: Bool {
        targetLanguageCodes.contains(TargetLanguage.default.rawValue) && targetLanguageCodes.count > 1
    }

    func loadLanguagePreferences() {
        let stored = projectPreferencesStore.value(for: .selectedLanguages)
        targetLanguageCodes = TargetLanguage.normalizeSelection(stored)
    }

    func isLanguageSelected(_ language: TargetLanguage) -> Bool {
        targetLanguageCodes.contains(language.rawValue)
    }

    func toggleLanguage(_ language: TargetLanguage) {
        var current = targetLanguageCodes
        if let index = current.firstIndex(of: language.rawValue) {
            if current.count == 1 {
                return
            }
            current.remove(at: index)
        } else {
            current.append(language.rawValue)
        }
        updateLanguageSelection(current)
    }

    func selectAllLanguages() {
        let all = TargetLanguage.allCases.map(\.rawValue)
        updateLanguageSelection(all)
    }

    func toggleAllLanguages() {
        if hasAllLanguagesSelected {
            updateLanguageSelection([TargetLanguage.default.rawValue])
        } else {
            selectAllLanguages()
        }
    }

    func removeEnglishLanguage() {
        guard canRemoveEnglishFromSelection else { return }
        var current = targetLanguageCodes.filter { $0 != TargetLanguage.default.rawValue }
        if current.isEmpty {
            current = [TargetLanguage.default.rawValue]
        }
        updateLanguageSelection(current)
    }

    private func updateLanguageSelection(_ codes: [String]) {
        let normalized = TargetLanguage.normalizeSelection(codes)
        targetLanguageCodes = normalized
        projectPreferencesStore.set(normalized, for: .selectedLanguages)
    }
}
