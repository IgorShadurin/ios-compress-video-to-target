import Foundation

struct DeviceMetadata: Codable {
    let deviceId: String
    let deviceName: String
    let platform: String
    let appVersion: String
}

struct MobileUser: Codable, Equatable {
    let id: String
    let email: String
    let name: String?
    let image: String?
}

struct SessionTokens: Codable, Equatable {
    let sessionId: String
    let userId: String
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date
}

struct MobileAuthResponse: Codable {
    let user: MobileUser
    let tokens: SessionTokens
    let provider: AuthProvider?
    let providerAccountId: String?
}

struct TokenSummaryResponse: Codable {
    let balance: Int
}

struct SubscriptionPurchaseResponse: Codable {
    let status: String
    let productId: String
    let transactionId: String
    let tokensGranted: Int
    let balance: Int
    let expiresAt: Date?
}

struct SubscriptionStatusResponse: Codable {
    let active: Bool
    let productId: String?
    let expiresAt: Date?
    let lastPurchaseAt: Date?
    let lastTransactionId: String?
    let environment: String?
}

struct AccountDeletionResponse: Codable {
    let status: String
    let message: String
}

enum AuthProvider: String, Codable {
    case google
    case apple
    case review
    case guest
}

struct AuthSession: Codable {
    let user: MobileUser
    let tokens: SessionTokens
    let provider: AuthProvider
    let providerAccountId: String?

    private enum CodingKeys: String, CodingKey {
        case user
        case tokens
        case provider
        case providerAccountId
    }

    init(user: MobileUser, tokens: SessionTokens, provider: AuthProvider, providerAccountId: String?) {
        self.user = user
        self.tokens = tokens
        self.provider = provider
        self.providerAccountId = providerAccountId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = try container.decode(MobileUser.self, forKey: .user)
        tokens = try container.decode(SessionTokens.self, forKey: .tokens)
        provider = try container.decodeIfPresent(AuthProvider.self, forKey: .provider) ?? .google
        providerAccountId = try container.decodeIfPresent(String.self, forKey: .providerAccountId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(user, forKey: .user)
        try container.encode(tokens, forKey: .tokens)
        try container.encode(provider, forKey: .provider)
        try container.encodeIfPresent(providerAccountId, forKey: .providerAccountId)
    }
}
