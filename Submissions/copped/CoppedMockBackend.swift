import Foundation

actor CoppedMockBackend {
    static let shared = CoppedMockBackend()

    private static let instantRewardCents = 500
    private static let conversionRewardCents = 500
    private static let fallbackVideoCatalog: [URL] = [
        URL(string: "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4")!,
        URL(string: "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4")!,
        URL(string: "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4")!,
    ]

    private struct RewardAccount {
        var walletCode: String
        var passURL: URL
        var availableBalanceCents: Int
        var lifetimeEarnedCents: Int
        var transactions: [CoppedRewardTransaction]
    }

    private struct PersistedState: Codable {
        let clips: [CoppedClip]
        let receipts: [CoppedReceipt]
        let orderCounter: Int
        let demoSeedKey: String?
    }

    private var clips: [String: CoppedClip] = [:]
    private var receipts: [String: CoppedReceipt] = [:]
    private var conversions: [CoppedConversion] = []
    private var latestPushByClipID: [String: CoppedNotificationEvent] = [:]
    private var rewardAccountsByDeviceID: [String: RewardAccount] = [:]
    private var orderCounter = 1000
    private var demoSeedKey: String?
    private var didRunLegacyMigration = false
    private let persistenceURL: URL

    private init() {
        persistenceURL = Self.makePersistenceURL()
        let seed = Self.makeSeedData()

        if let persisted = Self.loadPersistedState(from: persistenceURL) {
            clips = Dictionary(uniqueKeysWithValues: persisted.clips.map { ($0.id, $0) })
            receipts = Dictionary(uniqueKeysWithValues: persisted.receipts.map { ($0.id, $0) })
            orderCounter = persisted.orderCounter
            demoSeedKey = persisted.demoSeedKey
        } else {
            clips = seed.clips
            receipts = seed.receipts
            persistState()
        }
    }

    func getClips(productId: String) async -> [CoppedClip] {
        runLegacyVideoMigrationIfNeeded()
        try? await Task.sleep(nanoseconds: 200_000_000)

        return clips.values
            .filter { $0.productID == productId && $0.isActive }
            .sorted {
                if $0.conversions == $1.conversions {
                    return $0.createdAt > $1.createdAt
                }
                return $0.conversions > $1.conversions
            }
    }

    private func runLegacyVideoMigrationIfNeeded() {
        guard !didRunLegacyMigration else { return }
        didRunLegacyMigration = true
        if migrateLegacyVideoHosts() {
            persistState()
        }
    }

    func getReceipt(receiptId: String) async throws -> CoppedReceipt {
        try? await Task.sleep(nanoseconds: 150_000_000)

        guard let receipt = receipts[receiptId] else {
            throw CoppedBackendError.receiptNotFound
        }

        if receipt.clipCreated {
            throw CoppedBackendError.receiptAlreadyUsed
        }

        return receipt
    }

    func getReceiptIncludingUsed(receiptId: String) async throws -> CoppedReceipt {
        try? await Task.sleep(nanoseconds: 120_000_000)

        guard let receipt = receipts[receiptId] else {
            throw CoppedBackendError.receiptNotFound
        }

        return receipt
    }

    func ensureDemoReceipt(receiptId: String) -> CoppedReceipt {
        if let existing = receipts[receiptId] {
            return existing
        }

        let templateProducts = receipts["order_demo_hoodie"]?.productIDs ?? ["hoodie", "book", "food"]
        let receipt = CoppedReceipt(
            id: receiptId,
            productIDs: templateProducts,
            clipCreated: false,
            createdAt: Date()
        )
        receipts[receiptId] = receipt
        persistState()
        return receipt
    }

    func createUploadURL(receiptId: String, productId: String) async -> CoppedUploadURLResponse {
        let key = "clips/\(UUID().uuidString.lowercased()).mp4"
        let uploadURL = URL(string: "https://clipstakes.skilled5041.workers.dev/upload/\(key)")!
        let videoURL = Self.fallbackPlayableVideoURL(seed: key)

        return CoppedUploadURLResponse(
            uploadURL: uploadURL,
            videoURL: videoURL,
            key: key
        )
    }

    func createClip(
        receiptId: String,
        deviceID: String,
        productId: String,
        videoURL: URL,
        textOverlay: String?,
        textPosition: CoppedTextPosition,
        durationSeconds: Int
    ) async throws -> CoppedCreateClipResponse {
        guard (5...15).contains(durationSeconds) else {
            throw CoppedBackendError.invalidDuration
        }

        guard var receipt = receipts[receiptId] else {
            throw CoppedBackendError.invalidReceipt
        }

        if receipt.clipCreated {
            throw CoppedBackendError.receiptAlreadyUsed
        }

        let clipID = UUID().uuidString.lowercased()
        var account = ensureRewardAccount(for: deviceID)

        let clip = CoppedClip(
            id: clipID,
            receiptID: receiptId,
            creatorDeviceID: deviceID,
            productID: productId,
            videoURL: videoURL,
            textOverlay: textOverlay,
            textPosition: textPosition,
            durationSeconds: durationSeconds,
            couponCode: account.walletCode,
            couponRedeemed: false,
            conversions: 0,
            bonusCouponCode: nil,
            bonusPushed: false,
            bonusRedeemed: false,
            isActive: true,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(8 * 60 * 60)
        )

        clips[clipID] = clip
        receipt.clipCreated = true
        receipts[receiptId] = receipt
        persistState()

        account = credit(
            account: account,
            deviceID: deviceID,
            amountCents: Self.instantRewardCents,
            kind: .clipPublished,
            clipID: clipID,
            orderID: nil
        )

        return CoppedCreateClipResponse(
            clipID: clipID,
            walletCode: account.walletCode,
            instantCreditCents: Self.instantRewardCents,
            instantCreditDisplay: Self.instantRewardCents.coppedCurrencyDisplay,
            passURL: account.passURL,
            availableBalanceCents: account.availableBalanceCents,
            availableBalanceDisplay: account.availableBalanceCents.coppedCurrencyDisplay,
            message: "Clip is live. Credit added to your wallet balance."
        )
    }

    func logConversion(clipId: String, orderId: String) async throws -> CoppedConversionResponse {
        guard var clip = clips[clipId] else {
            throw CoppedBackendError.clipNotFound
        }

        let conversion = CoppedConversion(
            id: UUID().uuidString.lowercased(),
            clipID: clipId,
            orderID: orderId,
            createdAt: Date()
        )
        conversions.append(conversion)

        clip.conversions += 1
        let account = credit(
            account: ensureRewardAccount(for: clip.creatorDeviceID),
            deviceID: clip.creatorDeviceID,
            amountCents: Self.conversionRewardCents,
            kind: .conversion,
            clipID: clip.id,
            orderID: orderId
        )

        let withinPushWindow = Date() < clip.expiresAt
        if withinPushWindow {
            latestPushByClipID[clip.id] = CoppedNotificationEvent(
                clipID: clip.id,
                title: "Conversion reward earned",
                body: "\(Self.conversionRewardCents.coppedCurrencyDisplay) added to your wallet balance.",
                passURL: account.passURL,
                createdAt: Date()
            )
        }

        clips[clipId] = clip
        persistState()

        return CoppedConversionResponse(
            success: true,
            creditedCents: Self.conversionRewardCents,
            creditedDisplay: Self.conversionRewardCents.coppedCurrencyDisplay,
            availableBalanceCents: account.availableBalanceCents,
            availableBalanceDisplay: account.availableBalanceCents.coppedCurrencyDisplay,
            pushSent: withinPushWindow,
            withinPushWindow: withinPushWindow
        )
    }

    func createReceiptFromOrder(orderId: String, productIds: [String]) async -> CoppedReceipt {
        if let existing = receipts[orderId] {
            return existing
        }

        let receipt = CoppedReceipt(
            id: orderId,
            productIDs: productIds,
            clipCreated: false,
            createdAt: Date()
        )
        receipts[orderId] = receipt
        persistState()
        return receipt
    }

    func performViewerCheckout(productId: String, clipId: String?) async throws -> CoppedCheckoutOutcome {
        orderCounter += 1
        let orderId = "order_\(orderCounter)"
        let receipt = await createReceiptFromOrder(orderId: orderId, productIds: [productId])

        let conversionResult: CoppedConversionResponse?
        if let clipId {
            conversionResult = try await logConversion(clipId: clipId, orderId: orderId)
        } else {
            conversionResult = nil
        }

        return CoppedCheckoutOutcome(
            orderID: orderId,
            receiptID: receipt.id,
            conversion: conversionResult
        )
    }

    func latestNotification(for clipId: String) async -> CoppedNotificationEvent? {
        latestPushByClipID[clipId]
    }

    func getRewards(deviceID: String) async -> CoppedRewardsSnapshot {
        let account = ensureRewardAccount(for: deviceID)

        return CoppedRewardsSnapshot(
            walletCode: account.walletCode,
            passURL: account.passURL,
            availableBalanceCents: account.availableBalanceCents,
            availableBalanceDisplay: account.availableBalanceCents.coppedCurrencyDisplay,
            lifetimeEarnedCents: account.lifetimeEarnedCents,
            lifetimeEarnedDisplay: account.lifetimeEarnedCents.coppedCurrencyDisplay,
            transactions: Array(account.transactions.prefix(20))
        )
    }

    func prepareDemoCatalog(with products: [CoppedProduct]) {
        guard !products.isEmpty else { return }

        let primary = products[0].id
        let secondary = products.count > 1 ? products[1].id : primary
        let tertiary = products.count > 2 ? products[2].id : primary

        let key = "\(primary)|\(secondary)|\(tertiary)"
        guard key != demoSeedKey else { return }
        demoSeedKey = key

        let legacyMap: [String: String] = [
            "hoodie": primary,
            "book": secondary,
            "food": tertiary,
            "prod_hoodie": primary,
            "prod_vinyl": secondary,
            "prod_hat": tertiary,
            "prod_shirt": primary,
            "prod_poster": tertiary,
        ]
        let validIDs = Set(products.map(\.id))

        for clipID in clips.keys {
            guard var clip = clips[clipID] else { continue }
            if let mapped = legacyMap[clip.productID] {
                clip.productID = mapped
            } else if !validIDs.contains(clip.productID) {
                clip.productID = primary
            }
            clips[clipID] = clip
        }

        for receiptID in receipts.keys {
            guard var receipt = receipts[receiptID] else { continue }
            receipt.productIDs = receipt.productIDs.map { id in
                if let mapped = legacyMap[id] { return mapped }
                if validIDs.contains(id) { return id }
                return primary
            }
            receipts[receiptID] = receipt
        }

        receipts["order_demo_hoodie"] = CoppedReceipt(
            id: "order_demo_hoodie",
            productIDs: [primary, secondary, tertiary],
            clipCreated: false,
            createdAt: Date().addingTimeInterval(-3600)
        )

        receipts["order_demo_vinyl"] = CoppedReceipt(
            id: "order_demo_vinyl",
            productIDs: [secondary],
            clipCreated: false,
            createdAt: Date().addingTimeInterval(-2400)
        )
        persistState()
    }

    // MARK: - Seed Data

    private static func makeSeedData() -> (clips: [String: CoppedClip], receipts: [String: CoppedReceipt]) {
        var seededClips: [String: CoppedClip] = [:]
        var seededReceipts: [String: CoppedReceipt] = [:]

        let starterReceipts: [CoppedReceipt] = [
            CoppedReceipt(id: "order_demo_hoodie", productIDs: ["hoodie", "book", "food"], clipCreated: false, createdAt: Date().addingTimeInterval(-3600)),
            CoppedReceipt(id: "order_demo_vinyl", productIDs: ["book"], clipCreated: false, createdAt: Date().addingTimeInterval(-2400)),
        ]

        for receipt in starterReceipts {
            seededReceipts[receipt.id] = receipt
        }

        let sampleClips = [
            Self.makeSeedClip(
                clipId: "clip_seed_1",
                receiptId: "seed_receipt_1",
                productId: "hoodie",
                text: "OBSESSED",
                position: .bottom,
                conversions: 4,
                minutesAgo: 70,
                creatorDeviceID: "seed-device-1"
            ),
            Self.makeSeedClip(
                clipId: "clip_seed_2",
                receiptId: "seed_receipt_2",
                productId: "hoodie",
                text: "Runs true to size",
                position: .top,
                conversions: 2,
                minutesAgo: 20,
                creatorDeviceID: "seed-device-2"
            ),
            Self.makeSeedClip(
                clipId: "clip_seed_3",
                receiptId: "seed_receipt_3",
                productId: "book",
                text: "Sound quality is insane",
                position: .center,
                conversions: 1,
                minutesAgo: 35,
                creatorDeviceID: "seed-device-3"
            ),
        ]

        for clip in sampleClips {
            seededClips[clip.id] = clip
        }

        return (seededClips, seededReceipts)
    }

    private static func makeSeedClip(
        clipId: String,
        receiptId: String,
        productId: String,
        text: String,
        position: CoppedTextPosition,
        conversions: Int,
        minutesAgo: Int,
        creatorDeviceID: String
    ) -> CoppedClip {
        let created = Date().addingTimeInterval(TimeInterval(-60 * minutesAgo))

        return CoppedClip(
            id: clipId,
            receiptID: receiptId,
            creatorDeviceID: creatorDeviceID,
            productID: productId,
            videoURL: fallbackPlayableVideoURL(seed: clipId),
            textOverlay: text,
            textPosition: position,
            durationSeconds: 9,
            couponCode: Self.generateWalletCode(),
            couponRedeemed: false,
            conversions: conversions,
            bonusCouponCode: nil,
            bonusPushed: false,
            bonusRedeemed: false,
            isActive: true,
            createdAt: created,
            expiresAt: created.addingTimeInterval(8 * 60 * 60)
        )
    }

    private func ensureRewardAccount(for deviceID: String) -> RewardAccount {
        if let existing = rewardAccountsByDeviceID[deviceID] {
            return existing
        }

        let walletCode = Self.generateWalletCode()
        let passURL = URL(string: "https://clipstakes.skilled5041.workers.dev/wallet/\(walletCode)/pass")!
        let account = RewardAccount(
            walletCode: walletCode,
            passURL: passURL,
            availableBalanceCents: 0,
            lifetimeEarnedCents: 0,
            transactions: []
        )
        rewardAccountsByDeviceID[deviceID] = account
        return account
    }

    private func credit(
        account: RewardAccount,
        deviceID: String,
        amountCents: Int,
        kind: CoppedRewardTransaction.Kind,
        clipID: String,
        orderID: String?
    ) -> RewardAccount {
        var updated = account
        updated.availableBalanceCents += amountCents
        updated.lifetimeEarnedCents += amountCents

        let transaction = CoppedRewardTransaction(
            id: UUID().uuidString.lowercased(),
            kind: kind,
            amountCents: amountCents,
            amountDisplay: amountCents.coppedCurrencyDisplay,
            clipID: clipID,
            orderID: orderID,
            createdAt: Date()
        )
        updated.transactions.insert(transaction, at: 0)
        rewardAccountsByDeviceID[deviceID] = updated
        return updated
    }

    private static func generateWalletCode() -> String {
        let stamp = String(Int(Date().timeIntervalSince1970), radix: 36).uppercased()
        return "COP-\(stamp)-\(Int.random(in: 100...999))"
    }

    private static func makePersistenceURL() -> URL {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let stateDirectory = baseDirectory.appendingPathComponent("copped", isDirectory: true)
        try? fileManager.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        return stateDirectory.appendingPathComponent("mock-backend-state.json")
    }

    private func migrateLegacyVideoHosts() -> Bool {
        var didChange = false

        for (clipID, clip) in clips {
            guard clip.videoURL.host?.lowercased() == "r2.copped.app" else { continue }
            let replacement = Self.fallbackPlayableVideoURL(seed: clipID)
            guard replacement != clip.videoURL else { continue }

            clips[clipID] = Self.copy(clip: clip, replacingVideoURLWith: replacement)
            didChange = true
        }

        return didChange
    }

    private static func copy(clip: CoppedClip, replacingVideoURLWith videoURL: URL) -> CoppedClip {
        CoppedClip(
            id: clip.id,
            receiptID: clip.receiptID,
            creatorDeviceID: clip.creatorDeviceID,
            productID: clip.productID,
            videoURL: videoURL,
            textOverlay: clip.textOverlay,
            textPosition: clip.textPosition,
            durationSeconds: clip.durationSeconds,
            couponCode: clip.couponCode,
            couponRedeemed: clip.couponRedeemed,
            conversions: clip.conversions,
            bonusCouponCode: clip.bonusCouponCode,
            bonusPushed: clip.bonusPushed,
            bonusRedeemed: clip.bonusRedeemed,
            isActive: clip.isActive,
            createdAt: clip.createdAt,
            expiresAt: clip.expiresAt
        )
    }

    private static func fallbackPlayableVideoURL(seed: String) -> URL {
        let score = seed.unicodeScalars.reduce(into: 0) { partialResult, scalar in
            partialResult += Int(scalar.value)
        }
        let index = score % fallbackVideoCatalog.count
        return fallbackVideoCatalog[index]
    }

    private static func loadPersistedState(from url: URL) -> PersistedState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    private func persistState() {
        let snapshot = PersistedState(
            clips: Array(clips.values),
            receipts: Array(receipts.values),
            orderCounter: orderCounter,
            demoSeedKey: demoSeedKey
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: persistenceURL, options: [.atomic])
    }
}
