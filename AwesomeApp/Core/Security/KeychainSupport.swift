import Foundation
import Security

final class DeviceIdentifier {
    static let shared = DeviceIdentifier()
    private let keychain = KeychainItem(service: "com.awesomeapp.mobile", account: "device-id")
    private let lock = NSLock()

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        if let cached = keychain.readString(), !cached.isEmpty {
            return cached
        }
        let newValue = UUID().uuidString
        keychain.save(newValue)
        return newValue
    }
}

struct KeychainItem {
    let service: String
    let account: String

    func readData() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            return nil
        }
    }

    func readString() -> String? {
        guard let data = readData() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ data: Data) {
        delete()
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    func save(_ string: String) {
        if let data = string.data(using: .utf8) {
            save(data)
        }
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
