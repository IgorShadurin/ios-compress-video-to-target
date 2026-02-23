import Foundation
import os

extension AppViewModel {
    var characterButtonIndicatorActive: Bool {
        selectedCharacterSelection.source != .dynamic
    }

    var characterAccessibilityValue: String {
        option(for: selectedCharacterSelection)?.title ?? NSLocalizedString("character_dynamic_title", comment: "Default character title")
    }

    var dynamicCharacterOption: CharacterOption {
        let title = NSLocalizedString("character_dynamic_title", comment: "Default character title")
        let description = NSLocalizedString("character_dynamic_description", comment: "Default character description")
        return CharacterOption(
            id: "character-dynamic",
            source: .dynamic,
            characterId: nil,
            userCharacterId: nil,
            variationId: nil,
            title: title,
            description: description,
            imageURL: nil,
            status: .ready
        )
    }

    func loadCharacterSelectionPreference() {
        if let stored = projectPreferencesStore.value(for: .selectedCharacter) {
            selectedCharacterSelection = stored
        } else {
            selectedCharacterSelection = .dynamic
        }
    }

    func refreshCharacterOptions(force: Bool = false) {
        Task { await self.refreshCharacterOptionsAsync(force: force) }
    }

    private func refreshCharacterOptionsAsync(force: Bool) async {
        let shouldProceed = await MainActor.run { () -> Bool in
            if self.isLoadingCharacters && !force { return false }
            self.isLoadingCharacters = true
            self.characterLoadErrorMessage = nil
            return true
        }
        guard shouldProceed else { return }
        defer {
            Task { @MainActor in
                self.isLoadingCharacters = false
            }
        }

        // If the user is not signed in, skip fetching and show only the dynamic default option.
        if !isAuthenticated {
            await MainActor.run {
                self.characterOptionsGlobal = []
                self.characterOptionsUser = []
                self.characterLoadErrorMessage = nil
            }
            return
        }

        do {
            let session = try await ensureValidSession()
            let response = try await apiClient.fetchCharacterCollections(accessToken: session.tokens.accessToken)
            let global = Self.mapCharacterOptions(response.global, source: .global)
            let mine = Self.mapCharacterOptions(response.mine, source: .user)
            await MainActor.run {
                self.characterOptionsGlobal = global
                self.characterOptionsUser = mine
                self.characterLoadErrorMessage = nil
            }
        } catch {
            await MainActor.run {
                self.characterLoadErrorMessage = error.localizedDescription
                self.characterOptionsGlobal = []
                self.characterOptionsUser = []
            }
        }
    }

    func selectCharacter(option: CharacterOption) {
        guard option.isSelectable else { return }
        selectedCharacterSelection = option.selection
        projectPreferencesStore.set(option.selection, for: .selectedCharacter)
    }

    func resetCharacterSelection() {
        selectedCharacterSelection = .dynamic
        projectPreferencesStore.set(.dynamic, for: .selectedCharacter)
    }

    func isOptionSelected(_ option: CharacterOption) -> Bool {
        optionMatchesSelection(option, selection: selectedCharacterSelection)
    }

    func option(for selection: StoredCharacterSelection) -> CharacterOption? {
        if selection.source == .dynamic {
            return dynamicCharacterOption
        }
        let collections = characterOptionsUser + characterOptionsGlobal
        return collections.first { optionMatchesSelection($0, selection: selection) }
    }

    private func optionMatchesSelection(_ option: CharacterOption, selection: StoredCharacterSelection) -> Bool {
        guard option.source == selection.source else { return false }
        switch selection.source {
        case .dynamic:
            return true
        case .global:
            return option.characterId == selection.characterId && option.variationId == selection.variationId
        case .user:
            return option.userCharacterId == selection.userCharacterId && option.variationId == selection.variationId
        }
    }

    private static func mapCharacterOptions(
        _ records: [CharacterRecordResponse]?,
        source: CharacterSelectionSource
    ) -> [CharacterOption] {
        guard let records else { return [] }
        var options: [CharacterOption] = []
        for record in records {
            let variations = record.variations ?? []
            for variation in variations {
                let status: CharacterOption.Status
                switch variation.status {
                case "processing":
                    status = .processing
                case "failed":
                    status = .failed
                default:
                    status = .ready
                }
                let imageURL = makeAbsoluteURL(from: variation.imageUrl)
                options.append(
                    CharacterOption(
                        id: "\(record.id)-\(variation.id)",
                        source: source,
                        characterId: source == .global ? record.id : nil,
                        userCharacterId: source == .user ? record.id : nil,
                        variationId: variation.id,
                        title: variation.title ?? record.title,
                        description: variation.description ?? record.description,
                        imageURL: imageURL,
                        status: status
                    )
                )
            }
        }
        return options
    }

    private static func makeAbsoluteURL(from path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if let url = URL(string: path), url.scheme != nil {
            return url
        }
        return URL(string: path, relativeTo: AppConfiguration.apiBaseURL)
    }

    func uploadCustomCharacter(imageData: Data, fileName: String, mimeType: String, title: String, description: String?) async throws {
        let session = try await ensureValidSession()
        let grant = try await apiClient.createCharacterUploadToken(accessToken: session.tokens.accessToken)
        guard grant.mimeTypes.contains(mimeType) else {
            throw CharacterUploadError.unsupportedType
        }
        guard imageData.count <= grant.maxBytes else {
            throw CharacterUploadError.fileTooLarge(maxBytes: grant.maxBytes)
        }

        let storageResponse = try await uploadCharacterToStorage(
            imageData: imageData,
            fileName: fileName,
            mimeType: mimeType,
            grantData: grant.data,
            grantSignature: grant.signature
        )

        let payload = CompleteCharacterUploadRequest(
            data: storageResponse.data,
            signature: storageResponse.signature,
            path: storageResponse.path,
            url: storageResponse.url,
            title: title,
            description: description
        )

        let finalize = try await apiClient.finalizeCharacterUpload(payload, accessToken: session.tokens.accessToken)
        let selection = StoredCharacterSelection(
            source: .user,
            characterId: nil,
            userCharacterId: finalize.userCharacterId,
            variationId: finalize.variationId
        )

        await MainActor.run {
            self.selectedCharacterSelection = selection
            self.projectPreferencesStore.set(selection, for: .selectedCharacter)
        }

        await refreshCharacterOptionsAsync(force: true)
        await updatePreferredCharacter(selection)
    }

    private func uploadCharacterToStorage(
        imageData: Data,
        fileName: String,
        mimeType: String,
        grantData: String,
        grantSignature: String
    ) async throws -> StorageUploadResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        let uploadURL = AppConfiguration.storageBaseURL.appendingPathComponent(AppConfiguration.APIPath.userImageUpload)
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfiguration.storageUploadOrigin, forHTTPHeaderField: "Origin")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = multipartBody(
            boundary: boundary,
            fileName: fileName,
            mimeType: mimeType,
            fileData: imageData,
            grantData: grantData,
            grantSignature: grantSignature
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CharacterUploadError.storageUploadFailed(status: -1)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            logger.error("Storage upload failed: status=\(http.statusCode) body=\(body)")
            throw CharacterUploadError.storageUploadFailed(status: http.statusCode)
        }

        return try JSONDecoder.mobile.decode(StorageUploadResponse.self, from: data)
    }

    private func multipartBody(
        boundary: String,
        fileName: String,
        mimeType: String,
        fileData: Data,
        grantData: String,
        grantSignature: String
    ) -> Data {
        var body = Data()
        body.appendFormField(name: "file", filename: fileName, mimeType: mimeType, data: fileData, boundary: boundary)
        body.appendFormField(name: "data", value: grantData, boundary: boundary)
        body.appendFormField(name: "signature", value: grantSignature, boundary: boundary)
        body.appendString("--\(boundary)--\r\n")
        return body
    }

    private func updatePreferredCharacter(_ selection: StoredCharacterSelection) async {
        do {
            guard currentSession != nil else { return }
            var payload: [String: Any] = ["source": selection.source.rawValue]
            if let charId = selection.characterId { payload["characterId"] = charId }
            if let userCharId = selection.userCharacterId { payload["userCharacterId"] = userCharId }
            if let variationId = selection.variationId { payload["variationId"] = variationId }
            try await sendCharacterPreference(payload: payload)
        } catch {
            logger.error("Failed to persist preferred character: \(error.localizedDescription)")
        }
    }

    private func sendCharacterPreference(payload: [String: Any]) async throws {
        guard let session = try? await ensureValidSession() else { return }
        let value = CharacterPreferenceValue(
            source: payload["source"] as? String ?? "dynamic",
            characterId: payload["characterId"] as? String,
            userCharacterId: payload["userCharacterId"] as? String,
            variationId: payload["variationId"] as? String
        )
        _ = try await apiClient.updateUserSetting(key: "characterSelection", value: value, accessToken: session.tokens.accessToken)
    }
}

private struct CharacterPreferenceValue: Encodable {
    let source: String
    let characterId: String?
    let userCharacterId: String?
    let variationId: String?
}

private enum CharacterUploadError: LocalizedError {
    case unsupportedType
    case fileTooLarge(maxBytes: Int)
    case storageUploadFailed(status: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            return NSLocalizedString("character_upload_error_type", comment: "Invalid file type")
        case .fileTooLarge(let maxBytes):
            let megabytes = Double(maxBytes) / 1_048_576.0
            return String(format: NSLocalizedString("character_upload_error_size", comment: "File too large"), megabytes)
        case .storageUploadFailed(let status):
            return String(format: NSLocalizedString("character_upload_error_storage", comment: "Storage failure"), status)
        }
    }
}

private struct StorageUploadResponse: Decodable {
    let path: String
    let url: String
    let data: String
    let signature: String
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendFormField(name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString(value)
        appendString("\r\n")
    }

    mutating func appendFormField(name: String, filename: String, mimeType: String, data: Data, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }
}
