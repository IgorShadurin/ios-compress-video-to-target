import Foundation
import os

enum MobileAPIError: Error {
    case invalidURL
    case invalidResponse
    case missingIdToken
    case unauthorized
    case notSignedIn
    case server(String)
}

struct MobileAPIClient {
    // Template API scaffold:
    // - Keep this file as examples for auth/get/post/patch flows.
    // - Replace endpoint values and payload contracts for each new project.
    private enum Endpoint {
        static let authGoogle = "/v1/example/auth/google-sign-in"
        static let authApple = "/v1/example/auth/apple-sign-in"
        static let authEmail = "/v1/example/auth/email-sign-in"
        static let authGuest = "/v1/example/auth/guest-sign-in"
        static let authGuestUpgrade = "/v1/example/auth/guest-upgrade"
        static let authRefresh = "/v1/example/auth/refresh"
        static let authLogout = "/v1/example/auth/logout"
        static let tokenBalance = "/v1/example/account/token-balance"
        static let projects = "/v1/example/projects"
        static let voiceCatalog = "/v1/example/catalog/voices"
        static let templateCatalog = "/v1/example/catalog/templates?visibility=public"
        static let characters = "/v1/example/characters"
        static let characterUploadToken = "/v1/example/storage/upload-token"
        static let characterUploadFinalize = "/v1/example/characters/custom"
        static let userSettings = "/v1/example/user/settings"
        static let subscriptionPurchase = "/v1/example/subscriptions/purchase"
        static let subscriptionStatus = "/v1/example/subscriptions/status"
        static let accountDelete = "/v1/example/account/delete"

        static func projectDetail(_ id: String) -> String {
            "/v1/example/projects/\(id)"
        }
    }

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder = .mobile
    private let encoder: JSONEncoder = .mobile
    private let logger = Logger(subsystem: "com.awesomeapp.mobile", category: "API")

    init(baseURL: URL = AppConfiguration.apiBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func signInWithGoogle(idToken: String, metadata: DeviceMetadata) async throws -> MobileAuthResponse {
        struct Body: Encodable {
            let idToken: String
            let deviceId: String
            let deviceName: String
            let platform: String
            let appVersion: String
        }
        let payload = Body(
            idToken: idToken,
            deviceId: metadata.deviceId,
            deviceName: metadata.deviceName,
            platform: metadata.platform,
            appVersion: metadata.appVersion
        )
        let request = try makeRequest(path: Endpoint.authGoogle, method: "POST", body: payload)
        return try await send(request, decode: MobileAuthResponse.self)
    }

    func signInWithApple(identityToken: String, fullName: String?, metadata: DeviceMetadata) async throws -> MobileAuthResponse {
        struct Body: Encodable {
            let identityToken: String
            let fullName: String?
            let deviceId: String
            let deviceName: String
            let platform: String
            let appVersion: String
        }
        let payload = Body(
            identityToken: identityToken,
            fullName: fullName,
            deviceId: metadata.deviceId,
            deviceName: metadata.deviceName,
            platform: metadata.platform,
            appVersion: metadata.appVersion
        )
        let request = try makeRequest(path: Endpoint.authApple, method: "POST", body: payload)
        return try await send(request, decode: MobileAuthResponse.self)
    }

    func signInWithReview(email: String, password: String, metadata: DeviceMetadata) async throws -> MobileAuthResponse {
        struct Body: Encodable {
            let email: String
            let password: String
            let deviceId: String
            let deviceName: String
            let platform: String
            let appVersion: String
        }
        let payload = Body(
            email: email,
            password: password,
            deviceId: metadata.deviceId,
            deviceName: metadata.deviceName,
            platform: metadata.platform,
            appVersion: metadata.appVersion
        )
        let request = try makeRequest(path: Endpoint.authEmail, method: "POST", body: payload)
        return try await send(request, decode: MobileAuthResponse.self)
    }

    func signInAsGuest(metadata: DeviceMetadata) async throws -> MobileAuthResponse {
        struct Body: Encodable {
            let deviceId: String
            let deviceName: String
            let platform: String
            let appVersion: String
        }
        let payload = Body(
            deviceId: metadata.deviceId,
            deviceName: metadata.deviceName,
            platform: metadata.platform,
            appVersion: metadata.appVersion
        )
        let request = try makeRequest(path: Endpoint.authGuest, method: "POST", body: payload)
        return try await send(request, decode: MobileAuthResponse.self)
    }

    func upgradeGuestWithGoogle(idToken: String, metadata: DeviceMetadata, accessToken: String) async throws -> MobileAuthResponse {
        struct Body: Encodable {
            let provider: String = "google"
            let idToken: String
            let deviceId: String
            let deviceName: String
            let platform: String
            let appVersion: String
        }
        let payload = Body(
            idToken: idToken,
            deviceId: metadata.deviceId,
            deviceName: metadata.deviceName,
            platform: metadata.platform,
            appVersion: metadata.appVersion
        )
        let request = try makeRequest(path: Endpoint.authGuestUpgrade, method: "POST", body: payload, accessToken: accessToken)
        return try await send(request, decode: MobileAuthResponse.self)
    }

    func upgradeGuestWithApple(identityToken: String, fullName: String?, metadata: DeviceMetadata, accessToken: String) async throws -> MobileAuthResponse {
        struct Body: Encodable {
            let provider: String = "apple"
            let identityToken: String
            let fullName: String?
            let deviceId: String
            let deviceName: String
            let platform: String
            let appVersion: String
        }
        let payload = Body(
            identityToken: identityToken,
            fullName: fullName,
            deviceId: metadata.deviceId,
            deviceName: metadata.deviceName,
            platform: metadata.platform,
            appVersion: metadata.appVersion
        )
        let request = try makeRequest(path: Endpoint.authGuestUpgrade, method: "POST", body: payload, accessToken: accessToken)
        return try await send(request, decode: MobileAuthResponse.self)
    }

    func refresh(refreshToken: String, metadata: DeviceMetadata) async throws -> MobileAuthResponse {
        struct Body: Encodable {
            let refreshToken: String
            let deviceId: String?
            let deviceName: String?
            let platform: String?
            let appVersion: String?
        }
        let payload = Body(
            refreshToken: refreshToken,
            deviceId: metadata.deviceId,
            deviceName: metadata.deviceName,
            platform: metadata.platform,
            appVersion: metadata.appVersion
        )
        let request = try makeRequest(path: Endpoint.authRefresh, method: "POST", body: payload)
        return try await send(request, decode: MobileAuthResponse.self)
    }

    func logout(refreshToken: String) async throws {
        struct Body: Encodable { let refreshToken: String }
        let request = try makeRequest(path: Endpoint.authLogout, method: "POST", body: Body(refreshToken: refreshToken))
        _ = try await send(request, decode: SuccessResponse.self)
    }

    func fetchTokenBalance(accessToken: String) async throws -> Int {
        let request = try makeRequest(path: Endpoint.tokenBalance, method: "GET", body: EmptyBody(), accessToken: accessToken)
        let response = try await send(request, decode: TokenSummaryResponse.self)
        return response.balance
    }

    func fetchProjects(accessToken: String) async throws -> [ProjectListItemResponse] {
        let request = try makeRequest(path: Endpoint.projects, method: "GET", body: EmptyBody(), accessToken: accessToken)
        return try await send(request, decode: [ProjectListItemResponse].self)
    }

    func fetchVoiceOptions() async throws -> [VoiceOptionResponse] {
        let request = try makeRequest(path: Endpoint.voiceCatalog, method: "GET", body: EmptyBody())
        let response = try await send(request, decode: VoiceListResponse.self)
        return response.voices
    }

    func fetchTemplateOptions(accessToken: String?) async throws -> [TemplateOptionResponse] {
        let request = try makeRequest(
            path: Endpoint.templateCatalog,
            method: "GET",
            body: EmptyBody(),
            accessToken: accessToken
        )
        return try await send(request, decode: [TemplateOptionResponse].self)
    }

    func fetchCharacterCollections(accessToken: String) async throws -> CharacterCollectionsResponse {
        let request = try makeRequest(path: Endpoint.characters, method: "GET", body: EmptyBody(), accessToken: accessToken)
        return try await send(request, decode: CharacterCollectionsResponse.self)
    }

    func createCharacterUploadToken(accessToken: String) async throws -> CharacterUploadTokenResponse {
        let request = try makeRequest(path: Endpoint.characterUploadToken, method: "POST", body: EmptyBody(), accessToken: accessToken)
        return try await send(request, decode: CharacterUploadTokenResponse.self)
    }

    func finalizeCharacterUpload(_ payload: CompleteCharacterUploadRequest, accessToken: String) async throws -> CharacterUploadFinalizeResponse {
        let request = try makeRequest(path: Endpoint.characterUploadFinalize, method: "POST", body: payload, accessToken: accessToken)
        return try await send(request, decode: CharacterUploadFinalizeResponse.self)
    }

    func fetchUserSettings(accessToken: String) async throws -> UserSettingsResponse {
        let request = try makeRequest(path: Endpoint.userSettings, method: "GET", body: EmptyBody(), accessToken: accessToken)
        return try await send(request, decode: UserSettingsResponse.self)
    }

    func updateUserSetting<Value: Encodable>(key: String, value: Value, accessToken: String) async throws -> UserSettingsPatchResponse {
        let payload = PatchSettingRequest(key: key, value: value)
        let request = try makeRequest(path: Endpoint.userSettings, method: "PATCH", body: payload, accessToken: accessToken)
        return try await send(request, decode: UserSettingsPatchResponse.self)
    }

    func fetchProjectDetail(id: String, accessToken: String) async throws -> ProjectDetailResponse {
        let request = try makeRequest(path: Endpoint.projectDetail(id), method: "GET", body: EmptyBody(), accessToken: accessToken)
        return try await send(request, decode: ProjectDetailResponse.self)
    }

    func createProject(request payload: CreateProjectRequest, accessToken: String) async throws -> ProjectListItemResponse {
        let request = try makeRequest(path: Endpoint.projects, method: "POST", body: payload, accessToken: accessToken)
        return try await send(request, decode: ProjectListItemResponse.self)
    }

    func submitSubscriptionReceipt(receiptData: String?, signedTransactions: [String]? = nil, accessToken: String) async throws -> SubscriptionPurchaseResponse {
        struct Body: Encodable {
            let receiptData: String?
            let signedTransactions: [String]?
        }
        let payload = Body(
            receiptData: receiptData,
            signedTransactions: (signedTransactions?.isEmpty ?? true) ? nil : signedTransactions
        )
        let request = try makeRequest(path: Endpoint.subscriptionPurchase, method: "POST", body: payload, accessToken: accessToken)
        return try await send(request, decode: SubscriptionPurchaseResponse.self)
    }

    func fetchSubscriptionStatus(accessToken: String) async throws -> SubscriptionStatusResponse {
        let request = try makeRequest(
            path: Endpoint.subscriptionStatus,
            method: "GET",
            body: EmptyBody(),
            accessToken: accessToken
        )
        return try await send(request, decode: SubscriptionStatusResponse.self)
    }

    func deleteAccount(reason: String?, accessToken: String) async throws -> AccountDeletionResponse {
        struct Body: Encodable { let reason: String? }
        let request = try makeRequest(path: Endpoint.accountDelete, method: "POST", body: Body(reason: reason), accessToken: accessToken)
        return try await send(request, decode: AccountDeletionResponse.self)
    }

    private func makeRequest<T: Encodable>(
        path: String,
        method: String,
        body: T,
        accessToken: String? = nil
    ) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw MobileAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if !(body is EmptyBody) {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send<T: Decodable>(_ request: URLRequest, decode type: T.Type) async throws -> T {
        let method = request.httpMethod ?? "GET"
        let urlString = request.url?.absoluteString ?? "<unknown>"
        do {
#if targetEnvironment(simulator)
            logSimulatorEvent(.request(method: method, url: urlString, body: request.httpBody))
#endif
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
#if targetEnvironment(simulator)
                logSimulatorEvent(.error(method: method, url: urlString, description: "Missing HTTPURLResponse"))
#endif
                throw MobileAPIError.invalidResponse
            }
#if targetEnvironment(simulator)
            logSimulatorEvent(.response(method: method, url: urlString, statusCode: http.statusCode, body: data))
#endif
            switch http.statusCode {
            case 200..<300:
                return try decoder.decode(T.self, from: data)
            case 401:
                throw MobileAPIError.unauthorized
            default:
                let message = (try? JSONDecoder.mobile.decode(APIErrorResponse.self, from: data).error?.message)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let bodyString = String(data: data, encoding: .utf8) ?? "<binary>"
                let safeMessage = message?.isEmpty == false ? message! : HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
                logger.error("Request \(method, privacy: .public) \(urlString, privacy: .public) failed with status \(http.statusCode). Message: \(safeMessage, privacy: .public). Body: \(bodyString, privacy: .public)")
                throw MobileAPIError.server(safeMessage)
            }
        } catch {
            let nsError = error as NSError
            logger.error("Network request error for \(method, privacy: .public) \(urlString, privacy: .public): \(nsError.localizedDescription, privacy: .public) (code: \(nsError.code), domain: \(nsError.domain, privacy: .public))")
#if targetEnvironment(simulator)
            logSimulatorEvent(.error(method: method, url: urlString, description: nsError.localizedDescription))
#endif
            throw error
        }
    }

#if targetEnvironment(simulator)
    private enum SimulatorNetworkEvent {
        case request(method: String, url: String, body: Data?)
        case response(method: String, url: String, statusCode: Int, body: Data)
        case error(method: String, url: String, description: String)
    }

    private func logSimulatorEvent(_ event: SimulatorNetworkEvent) {
        let previewLimit = 2_048
        switch event {
        case let .request(method, url, body):
            let bodyPreview = previewString(from: body, limit: previewLimit) ?? "<empty>"
            print("📤 [SimAPI] \(method) \(url)\n\(bodyPreview)\n")
        case let .response(method, url, statusCode, body):
            let preview = previewString(from: body, limit: previewLimit) ?? "<empty>"
            print("📥 [SimAPI] \(method) \(url) [\(statusCode)]\n\(preview)\n")
        case let .error(method, url, description):
            print("⚠️ [SimAPI] \(method) \(url) error: \(description)\n")
        }
    }

    private func previewString(from data: Data?, limit: Int) -> String? {
        guard let data else { return nil }
        var string = String(data: data, encoding: .utf8) ?? "<binary>"
        if string.count > limit {
            let truncated = String(string.prefix(limit))
            string = "\(truncated)… (truncated)"
        }
        return string
    }
#endif

    private struct EmptyBody: Encodable {}
    private struct SuccessResponse: Decodable { let success: Bool? }
    private struct VoiceListResponse: Decodable { let voices: [VoiceOptionResponse] }
}

private struct APIErrorResponse: Decodable {
    struct ErrorInfo: Decodable {
        let message: String?
    }
    let error: ErrorInfo?
}

struct ProjectListItemResponse: Decodable {
    let id: String
    let title: String
    let status: String
    let createdAt: Date
}

struct ProjectDetailResponse: Decodable {
    let id: String
    let title: String
    let prompt: String?
    let rawScript: String?
    let status: String
    let createdAt: Date
    let finalVideoUrl: URL?
    let finalVideoPath: String?
    let languages: [String]?
    let creation: ProjectCreationResponse?
    let languageVariants: [ProjectLanguageVariantResponse]?
}

struct ProjectCreationResponse: Decodable {
    let durationSeconds: Int?
    let voiceId: String?
}

struct ProjectLanguageVariantResponse: Decodable {
    let languageCode: String
    let isPrimary: Bool?
    let finalVideoPath: String?
    let finalVideoUrl: String?
}

struct UserSettingsResponse: Decodable {
    let includeDefaultMusic: Bool
    let addOverlay: Bool
    let includeCallToAction: Bool
    let autoApproveScript: Bool
    let autoApproveAudio: Bool
    let watermarkEnabled: Bool
    let captionsEnabled: Bool
    let scriptCreationGuidanceEnabled: Bool
    let scriptCreationGuidance: String
    let audioStyleGuidanceEnabled: Bool
    let audioStyleGuidance: String
    let defaultUseScript: Bool
}

struct UserSettingsPatchResponse: Decodable {
    let includeDefaultMusic: Bool?
    let addOverlay: Bool?
    let includeCallToAction: Bool?
    let autoApproveScript: Bool?
    let autoApproveAudio: Bool?
    let watermarkEnabled: Bool?
    let captionsEnabled: Bool?
    let scriptCreationGuidanceEnabled: Bool?
    let scriptCreationGuidance: String?
    let audioStyleGuidanceEnabled: Bool?
    let audioStyleGuidance: String?
}

struct CreateProjectRequest: Encodable {
    let prompt: String
    let durationSeconds: Int?
    let characterSelection: CharacterSelection?
    let useExactTextAsScript: Bool
    let voiceId: String?
    let templateId: String?
    let languages: [String]

    struct CharacterSelection: Encodable {
        let source: String?
        let characterId: String?
        let userCharacterId: String?
        let variationId: String?
    }
}

struct TemplateOptionResponse: Decodable {
    struct TemplateAttribute: Decodable {
        let id: String
        let title: String
    }

    struct TemplateVoice: Decodable {
        let id: String
        let title: String
        let description: String?
        let externalId: String?
    }

    let id: String
    let title: String
    let description: String?
    let previewImageUrl: String?
    let previewVideoUrl: String?
    let isPublic: Bool
    let weight: Int?
    let createdAt: Date?
    let updatedAt: Date?
    let captionsStyle: TemplateAttribute?
    let overlay: TemplateAttribute?
    let artStyle: TemplateAttribute?
    let voice: TemplateVoice?
}

struct VoiceOptionResponse: Decodable {
    let id: String
    let title: String
    let description: String?
    let externalId: String?
    let languages: [String]?
    let speed: String?
    let gender: String?
    let previewPath: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, externalId, languages, speed, gender, previewPath
    }

    init(
        id: String,
        title: String,
        description: String?,
        externalId: String?,
        languages: [String]?,
        speed: String?,
        gender: String?,
        previewPath: String?
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.externalId = externalId
        self.languages = languages
        self.speed = speed
        self.gender = gender
        self.previewPath = previewPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let title = try container.decode(String.self, forKey: .title)
        let description = try container.decodeIfPresent(String.self, forKey: .description)
        let externalId = try container.decodeIfPresent(String.self, forKey: .externalId)
        let speed = try container.decodeIfPresent(String.self, forKey: .speed)
        let gender = try container.decodeIfPresent(String.self, forKey: .gender)
        let previewPath = try container.decodeIfPresent(String.self, forKey: .previewPath)

        let languages: [String]?
        if let array = try? container.decode([String].self, forKey: .languages) {
            languages = array
        } else if let csv = try? container.decode(String.self, forKey: .languages) {
            languages = csv
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        } else {
            languages = nil
        }

        self.init(
            id: id,
            title: title,
            description: description,
            externalId: externalId,
            languages: languages,
            speed: speed,
            gender: gender,
            previewPath: previewPath
        )
    }
}

private struct PatchSettingRequest: Encodable {
    let key: String
    let value: AnyEncodable

    init<T: Encodable>(key: String, value: T) {
        self.key = key
        self.value = AnyEncodable(value)
    }

    enum CodingKeys: String, CodingKey {
        case key
        case value
    }
}

struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        self.encodeClosure = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeClosure(encoder)
    }
}

struct CharacterCollectionsResponse: Decodable {
    let global: [CharacterRecordResponse]?
    let mine: [CharacterRecordResponse]?
}

struct CharacterRecordResponse: Decodable {
    let id: String
    let title: String
    let description: String?
    let variations: [CharacterVariationResponse]?
}

struct CharacterVariationResponse: Decodable {
    let id: String
    let title: String?
    let description: String?
    let imageUrl: String?
    let status: String?
}

struct CharacterUploadTokenResponse: Decodable {
    let data: String
    let signature: String
    let expiresAt: Date?
    let mimeTypes: [String]
    let maxBytes: Int
}

struct CompleteCharacterUploadRequest: Encodable {
    let data: String
    let signature: String
    let path: String
    let url: String
    let title: String
    let description: String?
}

struct CharacterUploadFinalizeResponse: Decodable {
    let userCharacterId: String
    let variationId: String
}
