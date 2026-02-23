import Foundation

final class SubscriptionStatusStore {
    private let keychain = KeychainItem(service: "com.awesomeapp.mobile", account: "subscription-status")

    func loadStatus(for userId: String?) -> Bool {
        guard let userId else { return false }
        return readStatuses()[userId] ?? false
    }

    func save(isSubscribed: Bool, for userId: String?) {
        guard let userId else { return }
        var statuses = readStatuses()
        if isSubscribed {
            statuses[userId] = true
        } else {
            statuses.removeValue(forKey: userId)
        }
        persist(statuses)
    }

    private func readStatuses() -> [String: Bool] {
        guard let data = keychain.readData(), !data.isEmpty else {
            return [:]
        }
        if let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            return decoded
        }
        keychain.delete()
        return [:]
    }

    private func persist(_ statuses: [String: Bool]) {
        if statuses.isEmpty {
            keychain.delete()
            return
        }
        if let data = try? JSONEncoder().encode(statuses) {
            keychain.save(data)
        }
    }
}
