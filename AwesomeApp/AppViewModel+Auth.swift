import Foundation
import GoogleSignIn
import AuthenticationServices
import os
import UIKit

extension AppViewModel {
    // MARK: - OAuth Linking

    func linkGoogleAccount() {
        guard connectedAccountEmail == nil, !isGoogleLinking else { return }
        guard let clientID = AppConfiguration.googleClientID else {
            authErrorMessage = NSLocalizedString("settings_auth_error", comment: "")
            return
        }
        guard let presenter = UIApplication.topViewController else {
            authErrorMessage = NSLocalizedString("settings_auth_error", comment: "")
            return
        }

        isGoogleLinking = true
        authErrorMessage = nil
        logger.log("Auth redrift: launching Google sign-in flow")
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        Task { [weak self] in
            guard let self else { return }
            defer { self.isGoogleLinking = false }
            do {
                let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
                guard let token = result.user.idToken?.tokenString else {
                    throw MobileAPIError.missingIdToken
                }

                if self.currentSession?.provider == .guest {
                    let session = try await self.ensureValidSession()
                    let response = try await self.apiClient.upgradeGuestWithGoogle(idToken: token, metadata: self.deviceMetadata, accessToken: session.tokens.accessToken)
                    let upgraded = AuthSession(
                        user: response.user,
                        tokens: response.tokens,
                        provider: .google,
                        providerAccountId: response.providerAccountId ?? result.user.userID
                    )
                    self.completeSignIn(with: upgraded)
                    self.logger.log("Auth redrift: guest upgraded via Google for \(upgraded.user.email, privacy: .public)")
                    await self.refreshTokenBalanceIfNeeded(force: true)
                    await self.refreshSubscriptionStatusFromServer()
                    return
                }

                let response = try await apiClient.signInWithGoogle(idToken: token, metadata: deviceMetadata)
                let session = AuthSession(
                    user: response.user,
                    tokens: response.tokens,
                    provider: response.provider ?? .google,
                    providerAccountId: response.providerAccountId ?? result.user.userID
                )
                completeSignIn(with: session)
                logger.log("Auth redrift: Google sign-in succeeded for \(session.user.email, privacy: .public); access expires at \(session.tokens.accessTokenExpiresAt as NSDate, privacy: .public)")
                await self.refreshTokenBalanceIfNeeded(force: true)
            } catch {
                if self.isGoogleCancellation(error) {
                    self.logger.log("Auth redrift: user cancelled Google sign-in")
                    return
                }
                let nsError = error as NSError
                self.logger.error("Google sign-in failed: \(nsError.localizedDescription, privacy: .public) (code: \(nsError.code), domain: \(nsError.domain, privacy: .public))")
                if !nsError.userInfo.isEmpty {
                    self.logger.debug("Google sign-in userInfo: \(String(describing: nsError.userInfo), privacy: .public)")
                }
                self.authErrorMessage = self.humanReadableMessage(for: error)
            }
        }
    }

    func linkAppleAccount() {
        guard connectedAccountEmail == nil, !isAppleLinking else { return }
        isAppleLinking = true
        authErrorMessage = nil
        logger.log("Auth redrift: launching Apple sign-in flow")

        Task { [weak self] in
            guard let self else { return }
            defer { self.isAppleLinking = false }
            do {
                let credential = try await self.appleSignInCoordinator.signIn(requestedScopes: [.fullName, .email])
                guard let tokenData = credential.identityToken,
                      let token = String(data: tokenData, encoding: .utf8) else {
                    throw MobileAPIError.missingIdToken
                }
                let fullName = credential.fullName.flatMap { Self.appleNameFormatter.string(from: $0) }

                if self.currentSession?.provider == .guest {
                    let session = try await self.ensureValidSession()
                    let response = try await self.apiClient.upgradeGuestWithApple(identityToken: token, fullName: fullName, metadata: self.deviceMetadata, accessToken: session.tokens.accessToken)
                    let upgraded = AuthSession(
                        user: response.user,
                        tokens: response.tokens,
                        provider: .apple,
                        providerAccountId: response.providerAccountId ?? credential.user
                    )
                    self.completeSignIn(with: upgraded)
                    self.logger.log("Auth redrift: guest upgraded via Apple for \(upgraded.user.email, privacy: .public)")
                    await self.refreshTokenBalanceIfNeeded(force: true)
                    await self.refreshSubscriptionStatusFromServer()
                    return
                }

                let response = try await self.apiClient.signInWithApple(identityToken: token, fullName: fullName, metadata: self.deviceMetadata)
                let session = AuthSession(
                    user: response.user,
                    tokens: response.tokens,
                    provider: .apple,
                    providerAccountId: response.providerAccountId ?? credential.user
                )
                self.completeSignIn(with: session)
                self.logger.log("Auth redrift: Apple sign-in succeeded for \(session.user.email, privacy: .public)")
                await self.refreshTokenBalanceIfNeeded(force: true)
            } catch {
                if self.isAppleCancellation(error) {
                    self.logger.log("Auth redrift: user cancelled Apple sign-in")
                    return
                }
                let nsError = error as NSError
                self.logger.error("Apple sign-in failed: \(nsError.localizedDescription, privacy: .public) (code: \(nsError.code), domain: \(nsError.domain, privacy: .public))")
                if !nsError.userInfo.isEmpty {
                    self.logger.debug("Apple sign-in userInfo: \(String(describing: nsError.userInfo), privacy: .public)")
                }
                self.authErrorMessage = self.humanReadableMessage(for: error)
            }
        }
    }

    func linkReviewAccount(email: String, password: String) {
        guard connectedAccountEmail == nil, !isReviewLinking else { return }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !trimmedPassword.isEmpty else {
            authErrorMessage = NSLocalizedString("signin_email_missing_fields", comment: "")
            return
        }

        isReviewLinking = true
        authErrorMessage = nil
        logger.log("Auth redrift: launching reviewer email sign-in flow")

        Task { [weak self] in
            guard let self else { return }
            defer { self.isReviewLinking = false }
            do {
                let response = try await self.apiClient.signInWithReview(email: trimmedEmail, password: trimmedPassword, metadata: self.deviceMetadata)
                let session = AuthSession(
                    user: response.user,
                    tokens: response.tokens,
                    provider: .review,
                    providerAccountId: response.providerAccountId ?? response.user.id
                )
                self.completeSignIn(with: session)
                self.logger.log("Auth redrift: reviewer email sign-in succeeded for \(session.user.email, privacy: .public)")
                await self.refreshTokenBalanceIfNeeded(force: true)
            } catch {
                let nsError = error as NSError
                self.logger.error("Reviewer sign-in failed: \(nsError.localizedDescription, privacy: .public)")
                self.authErrorMessage = self.humanReadableMessage(for: error)
            }
        }
    }

    private func completeSignIn(with session: AuthSession, refreshData: Bool = true) {
        authStore.save(session)
        currentSession = session
        authErrorMessage = nil
        dismissSignInSheet(clearPendingRequest: false)
        if refreshData {
            refreshProjectSummaries(force: true)
        }
        resumePendingGenerationFlowIfNeeded()
    }

    func presentSignInSheet() {
        isSignInSheetPresented = true
    }

    func dismissSignInSheet(clearPendingRequest: Bool = true) {
        isSignInSheetPresented = false
        if clearPendingRequest {
            pendingGenerationRequest = false
        }
    }

    func signOut() {
        guard !isSigningOut, let session = currentSession else { return }
        isSigningOut = true
        logger.log("Auth redrift: signing out user \(session.user.email, privacy: .public)")
        Task { [weak self] in
            guard let self else { return }
            defer { self.isSigningOut = false }
            try? await self.apiClient.logout(refreshToken: session.tokens.refreshToken)
            if session.provider == .google {
                GIDSignIn.sharedInstance.signOut()
            }
            self.clearSession()
            self.logger.log("Auth redrift: sign-out completed")
        }
    }

    func deleteAccount() {
        guard !isDeletingAccount else { return }
        guard currentSession != nil else {
            accountDeletionErrorMessage = NSLocalizedString("settings_auth_error", comment: "")
            return
        }
        isDeletingAccount = true
        accountDeletionErrorMessage = nil
        accountDeletionSuccessMessage = nil
        logger.log("Auth redrift: user initiated account deletion")
        Task { [weak self] in
            guard let self else { return }
            defer { self.isDeletingAccount = false }
            do {
                let session = try await self.ensureValidSession()
                let response = try await self.apiClient.deleteAccount(reason: "mobile_settings_user_requested", accessToken: session.tokens.accessToken)
                await MainActor.run {
                    let fallback = NSLocalizedString("settings_delete_account_success", comment: "")
                    self.accountDeletionSuccessMessage = response.message.isEmpty ? fallback : response.message
                    self.clearSession()
                    self.isSettingsPresented = false
                }
            } catch MobileAPIError.unauthorized, MobileAPIError.notSignedIn {
                await MainActor.run {
                    self.accountDeletionErrorMessage = NSLocalizedString("settings_auth_error", comment: "")
                    self.clearSession()
                }
            } catch {
                await MainActor.run {
                    self.accountDeletionErrorMessage = self.humanReadableMessage(for: error)
                }
            }
        }
    }

    func reloadTokenBalance() {
        Task { await refreshTokenBalanceIfNeeded(force: true) }
    }

    func ensureGuestSessionIfNeeded(force: Bool = false) async {
        if let session = currentSession {
            if session.provider != .guest {
                return
            }
            if !force {
                return
            }
        }

        if let task = guestSignInTask {
            _ = await task.value
            return
        }

        logger.log("Auth redrift: ensuring guest session (force: \(force))")
        guestSignInTask = Task<AuthSession?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.performGuestSignIn()
        }
        _ = await guestSignInTask?.value
        guestSignInTask = nil
    }

    func restorePreviousSessionIfNeeded(force: Bool = false) async {
        logger.log("Auth redrift: restorePreviousSessionIfNeeded(force: \(force)) invoked")
        guard force || shouldRestoreSession else {
            logger.log("Auth redrift: skipping restore (session still valid)")
            return
        }
        guard let provider = currentSession?.provider else {
            logger.error("Auth redrift: no provider available for restore")
            await ensureGuestSessionIfNeeded(force: true)
            await refreshTokenBalanceIfNeeded(force: true)
            return
        }
        guard await silentlyReauthenticate(provider: provider) != nil else {
            logger.error("Auth redrift: silent reauth failed during restore")
            return
        }
        await refreshTokenBalanceIfNeeded(force: true)
        refreshProjectSummaries(force: true)
    }

    @discardableResult
    private func silentlyReauthenticate(provider: AuthProvider) async -> AuthSession? {
        switch provider {
        case .google:
            return await silentlyReauthenticateWithGoogle()
        case .apple:
            return await silentlyReauthenticateWithApple()
        case .review:
            logger.log("Auth redrift: reviewer accounts do not support silent reauth; prompting manual login")
            return nil
        case .guest:
            return await performGuestSignIn()
        }
    }

    @discardableResult
    private func silentlyReauthenticateWithGoogle() async -> AuthSession? {
        guard let clientID = AppConfiguration.googleClientID else { return nil }
        logger.log("Auth redrift: attempting silent Google reauth")
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        do {
            guard let user = try await restoreGoogleUser() else { return nil }
            guard let token = user.idToken?.tokenString else {
                throw MobileAPIError.missingIdToken
            }
            let response = try await apiClient.signInWithGoogle(idToken: token, metadata: deviceMetadata)
            let session = AuthSession(
                user: response.user,
                tokens: response.tokens,
                provider: .google,
                providerAccountId: response.providerAccountId ?? user.userID
            )
            completeSignIn(with: session)
            logger.log("Auth redrift: silent Google reauth success for \(session.user.email, privacy: .public); refresh expires at \(session.tokens.refreshTokenExpiresAt as NSDate, privacy: .public)")
            return session
        } catch {
            logger.error("Auth redrift: silent Google session restore failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    @discardableResult
    private func silentlyReauthenticateWithApple() async -> AuthSession? {
        logger.log("Auth redrift: attempting silent Apple reauth")
        do {
            let credential = try await appleSignInCoordinator.performExistingAccountSetup()
            guard let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                throw MobileAPIError.missingIdToken
            }
            let response = try await apiClient.signInWithApple(identityToken: token, fullName: nil, metadata: deviceMetadata)
            let session = AuthSession(
                user: response.user,
                tokens: response.tokens,
                provider: .apple,
                providerAccountId: response.providerAccountId ?? credential.user
            )
            completeSignIn(with: session)
            logger.log("Auth redrift: silent Apple reauth success for \(session.user.email, privacy: .public)")
            return session
        } catch {
            logger.error("Auth redrift: silent Apple session restore failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func restoreGoogleUser() async throws -> GIDGoogleUser? {
        try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: user)
            }
        }
    }

    private func refreshSession(using refreshToken: String) async throws -> AuthSession {
        guard let session = currentSession else {
            throw MobileAPIError.notSignedIn
        }
        logger.log("Auth redrift: refreshing access token via API")
        let response = try await apiClient.refresh(refreshToken: refreshToken, metadata: deviceMetadata)
        let refreshed = AuthSession(user: response.user, tokens: response.tokens, provider: session.provider, providerAccountId: session.providerAccountId)
        authStore.save(refreshed)
        currentSession = refreshed
        logger.log("Auth redrift: refresh exchange succeeded; new access expiry \(refreshed.tokens.accessTokenExpiresAt as NSDate, privacy: .public)")
        return refreshed
    }

    func ensureValidSession() async throws -> AuthSession {
        if currentSession == nil {
            logger.log("Auth redrift: ensureValidSession detected nil session -> silent login")
            if let provider = authStore.load()?.provider,
               let restored = await silentlyReauthenticate(provider: provider) {
                return restored
            }
            await ensureGuestSessionIfNeeded(force: true)
        }

        guard let session = currentSession else { throw MobileAPIError.notSignedIn }

        if session.tokens.refreshTokenExpiresAt <= Date() {
            logger.error("Auth redrift: refresh token expired; attempting silent login")
            if let renewed = await silentlyReauthenticate(provider: session.provider) {
                return renewed
            }
            throw MobileAPIError.unauthorized
        }

        if session.tokens.refreshTokenExpiresAt.timeIntervalSinceNow < refreshTokenRenewalLeadTime {
            logger.log("Auth redrift: refresh token nearing expiry; proactively renewing")
            if let renewed = await silentlyReauthenticate(provider: session.provider) {
                return renewed
            }
        }

        if session.tokens.accessTokenExpiresAt.timeIntervalSinceNow < 60 {
            logger.log("Auth redrift: access token expiring soon; refreshing via API")
            return try await refreshSession(using: session.tokens.refreshToken)
        }

        return session
    }

    func refreshTokenBalanceIfNeeded(force: Bool = false, allowRecovery: Bool = true) async {
        guard currentSession != nil else { return }
        if isLoadingTokenBalance && !force { return }

        isLoadingTokenBalance = true
        let minimumVisibleDuration: UInt64 = 2_000_000_000
        let start = DispatchTime.now().uptimeNanoseconds

        do {
            logger.log("Auth redrift: refreshing token balance (force: \(force), allowRecovery: \(allowRecovery))")
            let session = try await ensureValidSession()
            let balance = try await apiClient.fetchTokenBalance(accessToken: session.tokens.accessToken)
            tokenBalance = balance
            logger.log("Auth redrift: token balance updated to \(balance)")
        } catch MobileAPIError.unauthorized, MobileAPIError.notSignedIn {
            logger.error("Auth redrift: token balance fetch unauthorized; attempting recovery \(allowRecovery)")
            if allowRecovery, let provider = currentSession?.provider, await silentlyReauthenticate(provider: provider) != nil {
                await refreshTokenBalanceIfNeeded(force: true, allowRecovery: false)
            } else {
                logger.error("Auth redrift: recovery failed, clearing session")
                clearSession()
            }
        } catch {
            logger.error("Auth redrift: token balance refresh failed with error: \(error.localizedDescription, privacy: .public)")
        }

        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        if elapsed < minimumVisibleDuration {
            try? await Task.sleep(nanoseconds: minimumVisibleDuration - elapsed)
        }
        isLoadingTokenBalance = false
    }

    private var shouldRestoreSession: Bool {
        guard let session = currentSession else { return true }
        return session.tokens.refreshTokenExpiresAt.timeIntervalSinceNow < refreshTokenRenewalLeadTime
    }

    private func humanReadableMessage(for error: Error) -> String {
        if let apiError = error as? MobileAPIError {
            switch apiError {
            case .server(let message):
                return message
            case .missingIdToken, .unauthorized, .notSignedIn:
                return NSLocalizedString("settings_auth_error", comment: "")
            default:
                break
            }
        }
        if let urlError = error as? URLError {
            return urlError.localizedDescription
        }
        let nsError = error as NSError
        return nsError.localizedDescription.isEmpty ? NSLocalizedString("settings_auth_error", comment: "") : nsError.localizedDescription
    }

    private var deviceMetadata: DeviceMetadata {
        DeviceMetadata(
            deviceId: DeviceIdentifier.shared.value,
            deviceName: UIDevice.current.name,
            platform: "iOS \(UIDevice.current.systemVersion)",
            appVersion: AppConfiguration.appVersion
        )
    }

    private func clearSession() {
        let previousUserId = currentSession?.user.id
        stopAllStatusPolling()
        currentSession = nil
        connectedAccountEmail = nil
        authStore.clear()
        tokenBalance = nil
        isSubscribed = false
        subscriptionStatus = nil
        subscriptionStore.save(isSubscribed: false, for: previousUserId)
        projectSummaries = []
        isProjectSubmissionInFlight = false
        projectCreationErrorMessage = nil
        dismissProjectDetail()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.ensureGuestSessionIfNeeded(force: true)
            await self.refreshTokenBalanceIfNeeded(force: true)
        }
    }

    private func isGoogleCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        if let signInError = GIDSignInError.Code(rawValue: nsError.code), signInError == .canceled {
            return true
        }
        return false
    }

    private func isAppleCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == ASAuthorizationError.errorDomain else { return false }
        if nsError.code == ASAuthorizationError.canceled.rawValue {
            return true
        }
        // Some dismissal flows (e.g., tap outside) report `.unknown` (1000).
        if nsError.code == ASAuthorizationError.unknown.rawValue {
            return true
        }
        return false
    }

    private func performGuestSignIn() async -> AuthSession? {
        do {
            let response = try await apiClient.signInAsGuest(metadata: deviceMetadata)
            let provider = response.provider ?? .guest
            let session = AuthSession(
                user: response.user,
                tokens: response.tokens,
                provider: provider,
                providerAccountId: response.providerAccountId ?? response.user.id
            )
            return await MainActor.run {
                self.completeSignIn(with: session, refreshData: false)
                self.logger.log("Auth redrift: guest session issued for user \(session.user.id, privacy: .public)")
                return session
            }
        } catch {
            logger.error("Auth redrift: guest sign-in failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static let appleNameFormatter: PersonNameComponentsFormatter = {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .default
        return formatter
    }()
}
