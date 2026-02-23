import Foundation

final class AuthSessionStore {
    private let keychain = KeychainItem(service: "com.awesomeapp.mobile", account: "auth-session")
    private let encoder: JSONEncoder = .mobile
    private let decoder: JSONDecoder = .mobile

    func load() -> AuthSession? {
        guard let data = keychain.readData() else { return nil }
        return try? decoder.decode(AuthSession.self, from: data)
    }

    func save(_ session: AuthSession) {
        guard let data = try? encoder.encode(session) else { return }
        keychain.save(data)
    }

    func clear() {
        keychain.delete()
    }
}
