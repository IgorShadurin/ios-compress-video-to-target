import SwiftUI
import StoreKit
import os

extension AppViewModel {
    enum SubscriptionFlowError: LocalizedError, Equatable {
        case productUnavailable
        case userCancelled
        case pending
        case missingReceipt
        case backend(String)
        case authentication

        var errorDescription: String? {
            switch self {
            case .productUnavailable:
                return NSLocalizedString("paywall_error_product_unavailable", comment: "Product unavailable")
            case .userCancelled:
                return NSLocalizedString("paywall_error_cancelled", comment: "Purchase cancelled")
            case .pending:
                return NSLocalizedString("paywall_error_pending", comment: "Purchase pending")
            case .missingReceipt:
                return NSLocalizedString("paywall_error_missing_receipt", comment: "Receipt missing")
            case .backend(let message):
                return message
            case .authentication:
                return NSLocalizedString("settings_auth_error", comment: "Authentication error")
            }
        }
    }

    // MARK: - Subscription Management

    func resetSubscription() {
        guard isSubscribed else { return }
        setSubscriptionActive(false)
        subscriptionStatus = nil
    }

    func restorePurchases() async -> RestoreOutcome {
        if isRestoringPurchases {
            return .failed(NSLocalizedString("restore_in_progress_message", comment: ""))
        }
#if targetEnvironment(simulator)
        return .failed(NSLocalizedString("restore_simulator_message", comment: ""))
#else
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

        do {
            let signedTransactions = await gatherCurrentSignedTransactions()
            let receipt = try await fetchReceiptAllowingMissing(forceRefresh: true)
            if (receipt == nil || receipt?.isEmpty == true) && signedTransactions.isEmpty {
                throw SubscriptionFlowError.missingReceipt
            }
            let response = try await submitReceiptToServer(
                receiptData: receipt,
                signedTransactions: signedTransactions.isEmpty ? nil : signedTransactions
            )
            let shouldPromptGuestLink = response.status == "already_processed" && currentSession?.provider == .guest
            await MainActor.run {
                self.tokenBalance = response.balance
                self.setSubscriptionActive(true)
            }
            await refreshTokenBalanceIfNeeded(force: true)
            await refreshSubscriptionStatusFromServer()
            await MainActor.run {
                self.showGuestUpgradeBannerIfNeeded()
            }
            return shouldPromptGuestLink ? .guestLinkRequired : .restored
        } catch SubscriptionFlowError.missingReceipt {
            return .notFound
        } catch SubscriptionFlowError.userCancelled {
            return .cancelled
        } catch let error as SubscriptionFlowError {
            return .failed(error.errorDescription ?? NSLocalizedString("settings_auth_error", comment: ""))
        } catch let storeError as StoreKitError {
            if case .userCancelled = storeError {
                return .cancelled
            }
            return .failed(storeError.localizedDescription)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(error.localizedDescription)
        }
#endif
    }

    func purchaseSubscription(plan: PaywallPlan) async throws {
#if targetEnvironment(simulator)
        throw SubscriptionFlowError.productUnavailable
#else
        guard let product = subscriptionProducts[plan] else {
            loadSubscriptionProductsIfNeeded()
            throw SubscriptionFlowError.productUnavailable
        }

        var options: Set<Product.PurchaseOption> = []
        if let token = appAccountToken() {
            options.insert(.appAccountToken(token))
        }

        let result = try await product.purchase(options: options)
        switch result {
        case .success(let verification):
            let transaction = try verify(verification)
            let signedPayloads = [verification.jwsRepresentation]
            let receipt = try await fetchReceiptAllowingMissing(forceRefresh: false)
            let response = try await submitReceiptToServer(
                receiptData: receipt,
                signedTransactions: signedPayloads
            )
            let resolvedPlan = PaywallPlan(productIdentifier: response.productId) ?? plan
            await MainActor.run {
                self.tokenBalance = response.balance
                self.completeSubscription(with: resolvedPlan)
            }
            await refreshTokenBalanceIfNeeded(force: true)
            await refreshSubscriptionStatusFromServer()
            await MainActor.run {
                self.showGuestUpgradeBannerIfNeeded()
            }
            await transaction.finish()
        case .userCancelled:
            throw SubscriptionFlowError.userCancelled
        case .pending:
            throw SubscriptionFlowError.pending
        @unknown default:
            throw SubscriptionFlowError.backend("Unknown StoreKit purchase result")
        }
#endif
    }

    func loadSubscriptionProductsIfNeeded() {
        if subscriptionProducts.count == PaywallPlan.allCases.count || isSubscriptionProductLoading {
            return
        }
        isSubscriptionProductLoading = true
        Task { [weak self] in
            guard let self else { return }
            let identifiers = Set(PaywallPlan.allCases.map(\.productIdentifier))
            do {
                let products = try await Product.products(for: Array(identifiers))
                var mapping: [PaywallPlan: Product] = [:]
                for product in products {
                    if let plan = PaywallPlan(productIdentifier: product.id) {
                        mapping[plan] = product
                    }
                }
                await MainActor.run {
                    self.subscriptionProducts.merge(mapping) { _, new in new }
                }
            } catch {
                self.logger.error("Subscription product fetch failed: \(error.localizedDescription, privacy: .public)")
            }
            await MainActor.run {
                self.isSubscriptionProductLoading = false
            }
        }
    }

    func completeSubscription(with plan: PaywallPlan) {
        setSubscriptionActive(true)
        if !isAuthenticated {
            isAuthenticated = true
        }
        let shouldResume = paywallContext == .creationRequest && pendingGenerationRequest
        pendingGenerationRequest = false
        isPaywallPresented = false
        let previousContext = paywallContext
        paywallContext = .manual
        if shouldResume && previousContext == .creationRequest {
            startGeneration()
        }
    }

    func presentPaywall(force: Bool = false, context: PaywallContext = .manual) {
        paywallContext = context
        if !force && canStartGenerationWithoutPaywall {
            return
        }
        guard isAuthenticated else {
            presentSignInSheet()
            return
        }
        loadSubscriptionProductsIfNeeded()
        isPaywallPresented = true
    }

    func dismissPaywall() {
        isPaywallPresented = false
    }

    func handlePaywallDismissed() {
        isPaywallPresented = false
        let shouldResume = paywallContext == .creationRequest && pendingGenerationRequest
        pendingGenerationRequest = false
        if shouldResume && hasPaidGenerationAccess {
            startGeneration()
        }
        paywallContext = .manual
    }

    var canStartGenerationWithoutPaywall: Bool {
        if isDemoModeActive {
            return true
        }
        return isAuthenticated && hasPaidGenerationAccess
    }

    var planStatusKey: LocalizedStringKey {
        isSubscribed ? LocalizedStringKey("plan_subscribed") : LocalizedStringKey("plan_free")
    }

    private func setSubscriptionActive(_ active: Bool) {
        if isSubscribed != active {
            isSubscribed = active
        }
        subscriptionStore.save(isSubscribed: active, for: currentSession?.user.id)
    }

    private func applySubscriptionState(appStoreActive: Bool, backendStatus: SubscriptionStatusResponse?) {
        if let backendStatus {
            subscriptionStatus = backendStatus
        }
        let finalState = appStoreActive || (backendStatus?.active ?? false)
        setSubscriptionActive(finalState)
    }

    private func fetchBackendSubscriptionStatus() async -> SubscriptionStatusResponse? {
        do {
            let session = try await ensureValidSession()
            return try await apiClient.fetchSubscriptionStatus(accessToken: session.tokens.accessToken)
        } catch MobileAPIError.unauthorized, MobileAPIError.notSignedIn {
            return nil
        } catch {
            logger.error("Subscription status fetch failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw SubscriptionFlowError.backend(error.localizedDescription)
        case .verified(let safe):
            return safe
        }
    }

    private func fetchLatestReceiptData(forceRefresh: Bool) async throws -> String {
        try await loadReceiptData(forceRefresh: forceRefresh, didRefresh: false)
    }

    private func loadReceiptData(forceRefresh: Bool, didRefresh: Bool) async throws -> String {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            throw SubscriptionFlowError.missingReceipt
        }

        if forceRefresh && !didRefresh {
            await refreshReceipt()
            return try await loadReceiptData(forceRefresh: false, didRefresh: true)
        }

        if !FileManager.default.fileExists(atPath: receiptURL.path) {
            if didRefresh {
                throw SubscriptionFlowError.missingReceipt
            }
            await refreshReceipt()
            return try await loadReceiptData(forceRefresh: false, didRefresh: true)
        }

        do {
            let data = try Data(contentsOf: receiptURL)
            if data.isEmpty {
                if didRefresh {
                    throw SubscriptionFlowError.missingReceipt
                }
                await refreshReceipt()
                return try await loadReceiptData(forceRefresh: false, didRefresh: true)
            }
            return data.base64EncodedString()
        } catch {
            if isMissingReceiptError(error) && !didRefresh {
                await refreshReceipt()
                return try await loadReceiptData(forceRefresh: false, didRefresh: true)
            }
            if isMissingReceiptError(error) {
                throw SubscriptionFlowError.missingReceipt
            }
            throw SubscriptionFlowError.backend(error.localizedDescription)
        }
    }

    @MainActor
    private func refreshReceipt() async {
        do {
            try await AppStore.sync()
        } catch {
            logger.error("AppStore.sync failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func isMissingReceiptError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError
    }

    private func fetchReceiptAllowingMissing(forceRefresh: Bool) async throws -> String? {
        do {
            return try await fetchLatestReceiptData(forceRefresh: forceRefresh)
        } catch SubscriptionFlowError.missingReceipt {
            logger.error("Receipt missing after AppStore.sync (forceRefresh=\(forceRefresh))")
            return nil
        }
    }

    private func gatherCurrentSignedTransactions() async -> [String] {
        var payloads = Set<String>()
        for plan in PaywallPlan.allCases {
            do {
                if let verification = await Transaction.latest(for: plan.productIdentifier) {
                    _ = try verify(verification)
                    payloads.insert(verification.jwsRepresentation)
                }
            } catch {
                logger.error("Transaction.latest failed for plan \(plan.productIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return Array(payloads)
    }

    private func appAccountToken() -> UUID? {
        guard let userId = currentSession?.user.id else { return nil }
        return UUID(uuidString: userId)
    }

    private func submitReceiptToServer(receiptData: String?, signedTransactions: [String]? = nil) async throws -> SubscriptionPurchaseResponse {
        let session = try await ensureValidSession()
        do {
            if (receiptData == nil || receiptData?.isEmpty == true) && (signedTransactions?.isEmpty ?? true) {
                throw SubscriptionFlowError.missingReceipt
            }
            return try await apiClient.submitSubscriptionReceipt(
                receiptData: receiptData,
                signedTransactions: signedTransactions,
                accessToken: session.tokens.accessToken
            )
        } catch let error as MobileAPIError {
            switch error {
            case .server(let message):
                throw SubscriptionFlowError.backend(message)
            case .unauthorized, .notSignedIn:
                throw SubscriptionFlowError.authentication
            default:
                throw SubscriptionFlowError.backend(error.localizedDescription)
            }
        } catch {
            throw SubscriptionFlowError.backend(error.localizedDescription)
        }
    }

    func refreshSubscriptionStatusFromAppStore() {
        guard isAuthenticated else { return }
        subscriptionStatusTask?.cancel()
        subscriptionStatusTask = Task.detached { [weak self] in
            guard let self else { return }
            async let appStoreStatus = self.isSubscriptionEntitlementActive()
            async let backendStatus = self.fetchBackendSubscriptionStatus()
            let (hasActivePlan, backendResponse) = await (appStoreStatus, backendStatus)
            await MainActor.run {
                self.applySubscriptionState(appStoreActive: hasActivePlan, backendStatus: backendResponse)
            }
        }
    }

    func refreshSubscriptionStatusFromServer() async {
        guard isAuthenticated else { return }
        if let status = await fetchBackendSubscriptionStatus() {
            applySubscriptionState(appStoreActive: isSubscribed, backendStatus: status)
        }
    }

    private func isSubscriptionEntitlementActive() async -> Bool {
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            guard PaywallPlan(productIdentifier: transaction.productID) != nil else { continue }
            if transaction.revocationDate == nil {
                if let expiration = transaction.expirationDate {
                    if expiration > Date() { return true }
                } else {
                    return true
                }
            }
        }
        return false
    }

    func startTransactionUpdatesListener() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = Task.detached { [weak self] in
            guard let self else { return }
            for await result in StoreKit.Transaction.updates {
                await self.processStoreKitUpdate(result)
            }
        }
    }

    @MainActor
    private func handleSuccessfulUpdateResponse(_ response: SubscriptionPurchaseResponse, fallbackPlan: PaywallPlan?) {
        let resolvedPlan = PaywallPlan(productIdentifier: response.productId) ?? fallbackPlan
        if let resolvedPlan {
            completeSubscription(with: resolvedPlan)
        } else {
            setSubscriptionActive(true)
        }
        tokenBalance = response.balance
    }

    private func processStoreKitUpdate(_ result: StoreKit.VerificationResult<StoreKit.Transaction>) async {
        do {
            guard isAuthenticated else { return }
            let transaction = try verify(result)
            await transaction.finish()
            let payload = result.jwsRepresentation
            let response = try await submitReceiptToServer(receiptData: nil, signedTransactions: [payload])
            await MainActor.run {
                let fallbackPlan = PaywallPlan(productIdentifier: transaction.productID)
                self.handleSuccessfulUpdateResponse(response, fallbackPlan: fallbackPlan)
            }
            await refreshTokenBalanceIfNeeded(force: true)
        } catch {
            logger.error("StoreKit update handling failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
