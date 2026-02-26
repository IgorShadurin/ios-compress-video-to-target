import Foundation
import StoreKit

struct PurchasePlanOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let priceText: String
    let isAvailable: Bool
}

enum PurchaseManagerError: LocalizedError {
    case productUnavailable
    case pending

    var errorDescription: String? {
        switch self {
        case .productUnavailable:
            return L10n.tr("This purchase option is currently unavailable.")
        case .pending:
            return L10n.tr("Purchase is pending approval.")
        }
    }
}

final class PurchaseManager {
    static let weeklyProductID = "org.icorpvideo.compress.weekly"
    static let monthlyProductID = "org.icorpvideo.compress.monthly"
    static let lifetimeProductID = "org.icorpvideo.compress.lifetime"

    static let productOrder = [
        weeklyProductID,
        monthlyProductID,
        lifetimeProductID
    ]

    private static let fallbackPriceByProductID: [String: String] = [
        weeklyProductID: "$0.99",
        monthlyProductID: "$2.99",
        lifetimeProductID: "$29.99"
    ]

    func loadPlanOptions() async -> [PurchasePlanOption] {
        let byID = await loadProductsByID()

        return Self.productOrder.map { id in
            if let product = byID[id] {
                return PurchasePlanOption(
                    id: id,
                    title: title(for: id),
                    subtitle: subtitle(for: id),
                    priceText: product.displayPrice,
                    isAvailable: true
                )
            }

            return PurchasePlanOption(
                id: id,
                title: title(for: id),
                subtitle: subtitle(for: id),
                priceText: fallbackPrice(for: id),
                isAvailable: false
            )
        }
    }

    func hasActiveEntitlement() async -> Bool {
        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification else {
                continue
            }
            guard Self.productOrder.contains(transaction.productID) else {
                continue
            }
            guard transaction.revocationDate == nil else {
                continue
            }
            if let expirationDate = transaction.expirationDate,
               expirationDate < Date()
            {
                continue
            }
            return true
        }

        return false
    }

    func purchase(productID: String) async throws -> Bool {
        let products = try await Product.products(for: [productID])
        guard let product = products.first else {
            throw PurchaseManagerError.productUnavailable
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                return true
            case .unverified:
                throw PurchaseManagerError.productUnavailable
            }
        case .pending:
            throw PurchaseManagerError.pending
        case .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    func restorePurchases() async throws -> Bool {
        try await AppStore.sync()
        return await hasActiveEntitlement()
    }

    private func loadProductsByID() async -> [String: Product] {
        guard let products = try? await Product.products(for: Self.productOrder) else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
    }

    private func title(for productID: String) -> String {
        switch productID {
        case Self.weeklyProductID:
            return L10n.tr("Weekly")
        case Self.monthlyProductID:
            return L10n.tr("Monthly")
        case Self.lifetimeProductID:
            return L10n.tr("Forever")
        default:
            return L10n.tr("Premium")
        }
    }

    private func subtitle(for productID: String) -> String {
        switch productID {
        case Self.weeklyProductID:
            return L10n.tr("Unlimited conversions, billed weekly")
        case Self.monthlyProductID:
            return L10n.tr("Unlimited conversions, billed monthly")
        case Self.lifetimeProductID:
            return L10n.tr("Unlimited conversions forever")
        default:
            return L10n.tr("Unlimited conversions")
        }
    }

    private func fallbackPrice(for productID: String) -> String {
        Self.fallbackPriceByProductID[productID] ?? "$0.00"
    }
}
