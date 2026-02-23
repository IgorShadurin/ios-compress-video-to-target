import Foundation

enum AppConfiguration {
    // Template defaults: replace with your backend domains in new projects.
    static let apiBaseURL: URL = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "MOBILE_API_BASE_URL") as? String,
           let url = URL(string: value) {
            return url
        }
        return URL(string: "https://api.example.com")!
    }()

    static let storageBaseURL: URL = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "STORAGE_BASE_URL") as? String,
           let url = URL(string: value) {
            return url
        }
        return URL(string: "https://storage.example.com")!
    }()

    static let storageUploadOrigin: String = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "STORAGE_UPLOAD_ORIGIN") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "https://app.example.com"
    }()

    enum APIPath {
        // Example direct upload route; replace with your storage service path.
        static let userImageUpload = "v1/example/storage/user-images"
    }

    static var googleClientID: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_IOS_CLIENT_ID") as? String,
              !value.isEmpty,
              value != "YOUR_IOS_CLIENT_ID.apps.googleusercontent.com" else {
            return nil
        }
        return value
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static let reviewLoginEmail: String = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "REVIEW_LOGIN_EMAIL") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }()
}
