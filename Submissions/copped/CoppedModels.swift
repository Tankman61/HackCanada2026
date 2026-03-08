import Foundation

enum CoppedTextPosition: String, Codable, CaseIterable, Identifiable {
    case top
    case center
    case bottom

    var id: String { rawValue }
}

enum CoppedVideoLook: String, Codable, CaseIterable, Identifiable {
    case none
    case rioHeat
    case goldenHour
    case coolTeal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "Natural"
        case .rioHeat: return "Rio Heat"
        case .goldenHour: return "Golden Hour"
        case .coolTeal: return "Cool Teal"
        }
    }
}

enum CoppedVideoSticker: String, Codable, CaseIterable, Identifiable {
    case none
    case shootingStar
    case dolphinSplash

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "No Sticker"
        case .shootingStar: return "Shooting Star"
        case .dolphinSplash: return "Dolphin Splash"
        }
    }
}

struct CoppedVideoEffectConfig: Codable, Hashable {
    var look: CoppedVideoLook
    var sticker: CoppedVideoSticker

    static let rioDefault = CoppedVideoEffectConfig(
        look: .rioHeat,
        sticker: .none
    )

    var isNeutral: Bool {
        look == .none && sticker == .none
    }
}

enum CoppedCaptureMode: String, Codable {
    case camera
    case simulator
}

struct CoppedRecordedVideo: Hashable {
    let fileURL: URL?
    let durationSeconds: Int
    let captureMode: CoppedCaptureMode
}

struct CoppedProduct: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let price: Double
    let systemImage: String
    let imageURL: URL?

    init(
        id: String,
        name: String,
        price: Double,
        systemImage: String,
        imageURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.systemImage = systemImage
        self.imageURL = imageURL
    }

    var formattedPrice: String {
        String(format: "$%.2f", price)
    }
}

enum CoppedCatalog {
    static let fallbackProducts: [CoppedProduct] = [
        CoppedProduct(id: "hoodie", name: "Hoodie", price: 75.00, systemImage: "tshirt.fill"),
        CoppedProduct(id: "book", name: "Book", price: 30.00, systemImage: "book.fill"),
        CoppedProduct(id: "food", name: "Food", price: 20.00, systemImage: "fork.knife"),
    ]

    private static let lock = NSLock()
    private static var runtimeProductsByID: [String: CoppedProduct] = {
        Dictionary(uniqueKeysWithValues: fallbackProducts.map { ($0.id, $0) })
    }()

    static func updatePublicProducts(_ products: [CoppedProduct]) {
        guard !products.isEmpty else { return }
        let normalized = products.map(normalizedDemoProduct)
        lock.lock()
        runtimeProductsByID = Dictionary(uniqueKeysWithValues: normalized.map { ($0.id, $0) })
        lock.unlock()
    }

    static func allProducts() -> [CoppedProduct] {
        lock.lock()
        let values = Array(runtimeProductsByID.values)
        lock.unlock()

        return values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func product(for id: String) -> CoppedProduct {
        let normalizedID = normalizedDemoProductID(id)

        lock.lock()
        let runtime = runtimeProductsByID[id] ?? runtimeProductsByID[normalizedID]
        lock.unlock()

        if let runtime {
            return runtime
        }

        return fallbackProducts.first(where: { $0.id == normalizedID })
            ?? CoppedProduct(
                id: normalizedID,
                name: normalizedID.replacingOccurrences(of: "_", with: " ").capitalized,
                price: 25.00,
                systemImage: "shippingbox.fill"
            )
    }

    static func canonicalProductID(_ id: String) -> String {
        normalizedDemoProductID(id)
    }

    static func backendCompatibleProductID(_ id: String) -> String {
        switch normalizedDemoProductID(id) {
        case "hoodie":
            return "prod_hoodie"
        case "book":
            return "prod_vinyl"
        case "food":
            return "prod_hat"
        default:
            return id
        }
    }

    static func queryProductIDs(for id: String) -> [String] {
        let canonical = normalizedDemoProductID(id)
        let variants: [String]
        switch canonical {
        case "hoodie":
            variants = [canonical, "prod_hoodie", "prod_shirt"]
        case "book":
            variants = [canonical, "prod_vinyl"]
        case "food":
            variants = [canonical, "prod_hat", "prod_poster"]
        default:
            variants = [id]
        }

        var seen = Set<String>()
        return variants.filter { seen.insert($0).inserted }
    }

    private static func normalizedDemoProduct(_ product: CoppedProduct) -> CoppedProduct {
        let normalizedID = normalizedDemoProductID(product.id)
        if normalizedID == product.id {
            return product
        }

        if let fallback = fallbackProducts.first(where: { $0.id == normalizedID }) {
            return CoppedProduct(
                id: normalizedID,
                name: fallback.name,
                price: product.price,
                systemImage: fallback.systemImage,
                imageURL: product.imageURL
            )
        }

        return CoppedProduct(
            id: normalizedID,
            name: product.name,
            price: product.price,
            systemImage: product.systemImage,
            imageURL: product.imageURL
        )
    }

    private static func normalizedDemoProductID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.isEmpty { return raw }

        switch lower {
        case "hoodie", "prod_hoodie", "prod_shirt", "tour_t-shirt", "tour t-shirt":
            return "hoodie"
        case "book", "prod_vinyl":
            return "book"
        case "food", "prod_hat", "prod_poster":
            return "food"
        default:
            return trimmed
        }
    }
}

struct CoppedClip: Identifiable, Codable, Hashable {
    let id: String
    let receiptID: String
    let creatorDeviceID: String
    var productID: String
    let videoURL: URL
    let textOverlay: String?
    let textPosition: CoppedTextPosition
    let durationSeconds: Int
    let couponCode: String
    var couponRedeemed: Bool
    var conversions: Int
    var bonusCouponCode: String?
    var bonusPushed: Bool
    var bonusRedeemed: Bool
    var isActive: Bool
    let createdAt: Date
    let expiresAt: Date

    var product: CoppedProduct {
        CoppedCatalog.product(for: productID)
    }
}

struct CoppedReceipt: Identifiable, Codable, Hashable {
    let id: String
    var productIDs: [String]
    var clipCreated: Bool
    let createdAt: Date

    var products: [CoppedProduct] {
        productIDs.map(CoppedCatalog.product(for:))
    }
}

struct CoppedConversion: Identifiable, Codable, Hashable {
    let id: String
    let clipID: String
    let orderID: String
    let createdAt: Date
}

struct CoppedUploadURLResponse: Hashable {
    let uploadURL: URL
    let videoURL: URL
    let key: String
}

struct CoppedCreateClipResponse: Hashable {
    let clipID: String
    let walletCode: String
    let instantCreditCents: Int
    let instantCreditDisplay: String
    let passURL: URL
    let availableBalanceCents: Int
    let availableBalanceDisplay: String
    let message: String
}

struct CoppedConversionResponse: Hashable {
    let success: Bool
    let creditedCents: Int
    let creditedDisplay: String
    let availableBalanceCents: Int
    let availableBalanceDisplay: String
    let pushSent: Bool
    let withinPushWindow: Bool
}

struct CoppedCheckoutOutcome: Hashable {
    let orderID: String
    let receiptID: String
    let conversion: CoppedConversionResponse?
}

struct CoppedValidationResult: Hashable {
    let isValid: Bool
    let message: String
    let confidence: Float
    let usedFoundationModels: Bool
}

struct CoppedNotificationEvent: Hashable {
    let clipID: String
    let title: String
    let body: String
    let passURL: URL?
    let createdAt: Date
}

struct CoppedRewardTransaction: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case clipPublished
        case conversion
    }

    let id: String
    let kind: Kind
    let amountCents: Int
    let amountDisplay: String
    let clipID: String
    let orderID: String?
    let createdAt: Date
}

struct CoppedRewardsSnapshot: Hashable {
    let walletCode: String
    let passURL: URL
    let availableBalanceCents: Int
    let availableBalanceDisplay: String
    let lifetimeEarnedCents: Int
    let lifetimeEarnedDisplay: String
    let transactions: [CoppedRewardTransaction]
}

enum CoppedBackendError: LocalizedError {
    case receiptNotFound
    case receiptAlreadyUsed
    case invalidReceipt
    case clipNotFound
    case invalidDuration

    var errorDescription: String? {
        switch self {
        case .receiptNotFound:
            return "Receipt not found. Try scanning a valid creator receipt QR."
        case .receiptAlreadyUsed:
            return "You already created a clip for this receipt."
        case .invalidReceipt:
            return "This receipt is invalid for Copped."
        case .clipNotFound:
            return "Clip not found."
        case .invalidDuration:
            return "Video must be between 5 and 15 seconds."
        }
    }
}

extension Date {
    nonisolated func coppedRelativeDescription(reference: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: reference)
    }
}

extension Int {
    nonisolated var coppedCurrencyDisplay: String {
        String(format: "$%.2f", Double(self) / 100.0)
    }
}
