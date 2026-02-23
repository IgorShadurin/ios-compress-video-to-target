//
//  LanguageManager.swift
//  AwesomeApp
//
//  Created by test on 4.11.25.
//

import Combine
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case russian = "ru"
    case spanish = "es"

    var id: String { rawValue }

    var localizedTitle: LocalizedStringKey {
        switch self {
        case .english:
            return LocalizedStringKey("language_english")
        case .russian:
            return LocalizedStringKey("language_russian")
        case .spanish:
            return LocalizedStringKey("language_spanish")
        }
    }
}

final class LanguageManager: ObservableObject {
    @Published var selectedLanguage: AppLanguage {
        didSet {
            guard oldValue != selectedLanguage else { return }
            locale = Locale(identifier: selectedLanguage.rawValue)
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: storageKey)
        }
    }

    @Published private(set) var locale: Locale

    private let storageKey = "app_language_preference"

    init() {
        if let stored = UserDefaults.standard.string(forKey: storageKey),
           let language = AppLanguage(rawValue: stored) {
            _selectedLanguage = Published(initialValue: language)
            _locale = Published(initialValue: Locale(identifier: language.rawValue))
        } else {
            let fallback: AppLanguage = .english
            _selectedLanguage = Published(initialValue: fallback)
            _locale = Published(initialValue: Locale(identifier: fallback.rawValue))
        }
    }
}
