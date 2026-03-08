import Foundation

enum CoppedRemoteBackendError: LocalizedError {
    case network(URLError)
    case requestFailed(statusCode: Int, message: String)
    case invalidResponse(String)

    var isConnectivityIssue: Bool {
        switch self {
        case .network(let error):
            switch error.code {
            case .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .timedOut:
                return true
            default:
                return false
            }
        case .requestFailed, .invalidResponse:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .network(let error):
            return error.localizedDescription
        case .requestFailed(_, let message):
            return message
        case .invalidResponse(let message):
            return message
        }
    }
}

enum CoppedRemoteBackend {
    nonisolated static let defaultAPIBaseURL = URL(string: "https://clipstakes.skilled5041.workers.dev")!

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        return URLSession(configuration: configuration)
    }()

    nonisolated static func resolveAPIBaseURL(override: String?) -> URL {
        if let override, let url = normalizedURL(from: override) {
            return url
        }

        if let persisted = UserDefaults.standard.string(forKey: "copped.api_base_url"),
           let url = normalizedURL(from: persisted) {
            return url
        }

        return defaultAPIBaseURL
    }

    nonisolated static func fallbackWalletPassURL(apiBaseURL: URL, walletCode: String) -> URL {
        apiBaseURL
            .appendingPathComponent("wallet")
            .appendingPathComponent(walletCode)
            .appendingPathComponent("pass")
    }

    static func getReceipt(
        receiptId: String,
        apiBaseURL: URL,
        deviceID: String
    ) async throws -> CoppedReceipt {
        do {
            let response = try await requestJSON(
                apiBaseURL: apiBaseURL,
                paths: ["/receipt/\(receiptId)"],
                method: "GET",
                deviceID: deviceID,
                body: nil
            )
            let payload = payloadDict(from: response)

            let productIDs = productIDsFromReceiptPayload(payload)
            let clipCreated = boolValue(for: ["clip_created", "clipCreated"], in: payload) ?? false
            let createdAt = dateValue(for: ["created_at", "createdAt"], in: payload) ?? Date()

            guard !productIDs.isEmpty else {
                throw CoppedRemoteBackendError.invalidResponse("Receipt response did not include product IDs.")
            }

            return CoppedReceipt(
                id: receiptId,
                productIDs: productIDs,
                clipCreated: clipCreated,
                createdAt: createdAt
            )
        } catch let error as CoppedRemoteBackendError {
            if case .requestFailed(let statusCode, _) = error {
                if statusCode == 404 { throw CoppedBackendError.receiptNotFound }
                if statusCode == 409 || statusCode == 422 { throw CoppedBackendError.receiptAlreadyUsed }
            }
            throw error
        }
    }

    static func createUploadURL(
        receiptId: String,
        productId: String,
        apiBaseURL: URL,
        deviceID: String
    ) async throws -> CoppedUploadURLResponse {
        let requestBody: [String: Any] = [
            "receipt_id": receiptId,
            "product_id": productId
        ]

        let response = try await requestJSON(
            apiBaseURL: apiBaseURL,
            paths: ["/upload", "/upload-url"],
            method: "POST",
            deviceID: deviceID,
            body: requestBody
        )

        let payload = payloadDict(from: response)
        guard let uploadURLString = stringValue(for: ["upload_url", "uploadURL"], in: payload),
              let videoURLString = stringValue(for: ["video_url", "videoURL"], in: payload),
              let uploadURL = makeURL(from: uploadURLString, apiBaseURL: apiBaseURL),
              let videoURL = makeURL(from: videoURLString, apiBaseURL: apiBaseURL)
        else {
            throw CoppedRemoteBackendError.invalidResponse("Upload response missing upload_url or video_url.")
        }

        let key = stringValue(for: ["key"], in: payload)
            ?? videoURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        return CoppedUploadURLResponse(
            uploadURL: uploadURL,
            videoURL: videoURL,
            key: key
        )
    }

    static func createClip(
        receiptId: String,
        deviceID: String,
        productId: String,
        videoURL: URL,
        textOverlay: String?,
        textPosition: CoppedTextPosition,
        durationSeconds: Int,
        apiBaseURL: URL
    ) async throws -> CoppedCreateClipResponse {
        var requestBody: [String: Any] = [
            "receipt_id": receiptId,
            "product_id": productId,
            "video_url": videoURL.absoluteString,
            "text_position": textPosition.rawValue,
            "duration_seconds": durationSeconds
        ]
        if let textOverlay, !textOverlay.isEmpty {
            requestBody["text_overlay"] = textOverlay
        }

        do {
            let response = try await requestJSON(
                apiBaseURL: apiBaseURL,
                paths: ["/clips"],
                method: "POST",
                deviceID: deviceID,
                body: requestBody
            )
            let payload = payloadDict(from: response)
            let wallet = dictValue(for: ["wallet"], in: payload) ?? [:]
            let reward = dictValue(for: ["reward"], in: payload) ?? [:]
            let balances = dictValue(for: ["balances", "totals"], in: payload) ?? [:]

            let clipID = stringValue(for: ["clip_id", "clipId", "id"], in: payload)
                ?? UUID().uuidString.lowercased()

            guard let walletCode = stringValue(
                for: ["code", "wallet_code", "walletCode", "coupon_code", "couponCode"],
                in: wallet,
                fallback: payload
            ) else {
                throw CoppedRemoteBackendError.invalidResponse("Clip response missing wallet code.")
            }

            let backendPassURL = urlValue(
                for: ["pass_url", "wallet_pass_url", "passURL", "url"],
                in: wallet,
                apiBaseURL: apiBaseURL
            ) ?? urlValue(
                for: ["pass_url", "wallet_pass_url", "passURL"],
                in: payload,
                apiBaseURL: apiBaseURL
            )

            let passURL = backendPassURL ?? fallbackWalletPassURL(apiBaseURL: apiBaseURL, walletCode: walletCode)

            let instantCreditCents = intValue(
                for: ["instant_credit_cents", "instantCreditCents", "credited_cents", "creditedCents"],
                in: reward,
                fallback: payload
            ) ?? 0

            let availableBalanceCents = intValue(
                for: ["available_cents", "available_balance_cents", "availableBalanceCents", "balance_cents", "balanceCents"],
                in: balances,
                fallback: payload
            ) ?? 0

            let message = stringValue(for: ["message"], in: payload)
                ?? "Clip created."

            return CoppedCreateClipResponse(
                clipID: clipID,
                walletCode: walletCode,
                instantCreditCents: instantCreditCents,
                instantCreditDisplay: instantCreditCents.coppedCurrencyDisplay,
                passURL: passURL,
                availableBalanceCents: availableBalanceCents,
                availableBalanceDisplay: availableBalanceCents.coppedCurrencyDisplay,
                message: message
            )
        } catch let error as CoppedRemoteBackendError {
            if case .requestFailed(let statusCode, _) = error, statusCode == 409 {
                throw CoppedBackendError.receiptAlreadyUsed
            }
            throw error
        }
    }

    static func getRewards(
        deviceID: String,
        apiBaseURL: URL
    ) async throws -> CoppedRewardsSnapshot {
        let response = try await requestJSON(
            apiBaseURL: apiBaseURL,
            paths: ["/rewards/me"],
            method: "GET",
            deviceID: deviceID,
            body: nil
        )

        let payload = payloadDict(from: response)
        let wallet = dictValue(for: ["wallet"], in: payload) ?? payload
        let balances = dictValue(for: ["balances", "totals"], in: payload) ?? [:]

        guard let walletCode = stringValue(
            for: ["code", "wallet_code", "walletCode", "coupon_code", "couponCode"],
            in: wallet,
            fallback: payload
        ) else {
            throw CoppedRemoteBackendError.invalidResponse("Rewards response missing wallet code.")
        }

        let passURL = urlValue(
            for: ["pass_url", "wallet_pass_url", "passURL", "url"],
            in: wallet,
            apiBaseURL: apiBaseURL
        ) ?? urlValue(
            for: ["pass_url", "wallet_pass_url", "passURL"],
            in: payload,
            apiBaseURL: apiBaseURL
        ) ?? fallbackWalletPassURL(apiBaseURL: apiBaseURL, walletCode: walletCode)

        let availableBalanceCents = intValue(
            for: ["available_cents", "available_balance_cents", "availableBalanceCents", "balance_cents", "balanceCents"],
            in: balances,
            fallback: wallet
        ) ?? intValue(
            for: ["available_cents", "available_balance_cents", "availableBalanceCents", "balance_cents", "balanceCents"],
            in: wallet,
            fallback: payload
        ) ?? 0

        let lifetimeEarnedCents = intValue(
            for: ["lifetime_earned_cents", "lifetimeEarnedCents"],
            in: balances,
            fallback: wallet
        ) ?? intValue(
            for: ["lifetime_earned_cents", "lifetimeEarnedCents"],
            in: wallet,
            fallback: payload
        ) ?? availableBalanceCents

        let transactions = parseTransactions(
            from: arrayValue(for: ["transactions"], in: payload)
                ?? arrayValue(for: ["transactions"], in: wallet)
                ?? []
        )

        return CoppedRewardsSnapshot(
            walletCode: walletCode,
            passURL: passURL,
            availableBalanceCents: availableBalanceCents,
            availableBalanceDisplay: availableBalanceCents.coppedCurrencyDisplay,
            lifetimeEarnedCents: lifetimeEarnedCents,
            lifetimeEarnedDisplay: lifetimeEarnedCents.coppedCurrencyDisplay,
            transactions: transactions
        )
    }

    static func getClips(
        productId: String,
        apiBaseURL: URL,
        deviceID: String
    ) async throws -> [CoppedClip] {
        let response = try await requestJSON(
            apiBaseURL: apiBaseURL,
            paths: ["/clips/\(productId)"],
            method: "GET",
            deviceID: deviceID,
            body: nil
        )

        let payload = payloadDict(from: response)
        let rawClips = arrayValue(for: ["clips", "items", "data"], in: payload)
            ?? arrayValue(for: ["clips", "items", "data"], in: response)
            ?? []

        let parsed = rawClips.compactMap { parseClip(from: $0, fallbackProductId: productId, apiBaseURL: apiBaseURL) }
        return parsed
            .filter(\.isActive)
            .sorted {
                if $0.conversions == $1.conversions {
                    return $0.createdAt > $1.createdAt
                }
                return $0.conversions > $1.conversions
            }
    }

    static func performCheckout(
        productId: String,
        clipId: String?,
        apiBaseURL: URL,
        deviceID: String
    ) async throws -> CoppedCheckoutOutcome {
        var requestBody: [String: Any] = [
            "product_id": productId
        ]
        if let clipId, !clipId.isEmpty {
            requestBody["clip_id"] = clipId
        }

        let response = try await requestJSON(
            apiBaseURL: apiBaseURL,
            paths: ["/checkout/dev"],
            method: "POST",
            deviceID: deviceID,
            body: requestBody
        )

        let payload = payloadDict(from: response)
        guard let orderID = stringValue(for: ["order_id", "orderId"], in: payload),
              let receiptID = stringValue(for: ["receipt_id", "receiptId"], in: payload) else {
            throw CoppedRemoteBackendError.invalidResponse("Checkout response missing order_id or receipt_id.")
        }

        let conversion = dictValue(for: ["conversion"], in: payload).flatMap(parseConversionResponse(from:))

        return CoppedCheckoutOutcome(
            orderID: orderID,
            receiptID: receiptID,
            conversion: conversion
        )
    }

    // MARK: - Networking

    private static func requestJSON(
        apiBaseURL: URL,
        paths: [String],
        method: String,
        deviceID: String,
        body: [String: Any]?
    ) async throws -> [String: Any] {
        var lastError: Error?

        for path in paths {
            do {
                return try await requestJSON(
                    apiBaseURL: apiBaseURL,
                    path: path,
                    method: method,
                    deviceID: deviceID,
                    body: body
                )
            } catch let error as CoppedRemoteBackendError {
                lastError = error
                if case .requestFailed(let statusCode, _) = error, statusCode == 404 {
                    continue
                }
                throw error
            } catch {
                lastError = error
                throw error
            }
        }

        throw (lastError as? CoppedRemoteBackendError)
            ?? CoppedRemoteBackendError.invalidResponse("No valid backend endpoint found.")
    }

    private static func requestJSON(
        apiBaseURL: URL,
        path: String,
        method: String,
        deviceID: String,
        body: [String: Any]?
    ) async throws -> [String: Any] {
        let url = urlForPath(path, apiBaseURL: apiBaseURL)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(deviceID, forHTTPHeaderField: "X-Device-ID")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CoppedRemoteBackendError.invalidResponse("Backend returned a non-HTTP response.")
            }

            let object = try jsonObject(from: data)
            if (200 ... 299).contains(httpResponse.statusCode) {
                return object
            }

            let payload = payloadDict(from: object)
            let message = stringValue(for: ["message", "error", "detail"], in: payload)
                ?? stringValue(for: ["message", "error", "detail"], in: object)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)

            throw CoppedRemoteBackendError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: message
            )
        } catch let error as URLError {
            throw CoppedRemoteBackendError.network(error)
        } catch let error as CoppedRemoteBackendError {
            throw error
        } catch {
            throw CoppedRemoteBackendError.invalidResponse(error.localizedDescription)
        }
    }

    // MARK: - Parsing

    private static func parseTransactions(from raw: [[String: Any]]) -> [CoppedRewardTransaction] {
        raw.compactMap { item in
            let amount = intValue(for: ["amount_cents", "amountCents", "amount"], in: item) ?? 0
            let kindRaw = stringValue(for: ["kind", "type", "event"], in: item)?.lowercased() ?? ""
            let kind: CoppedRewardTransaction.Kind = kindRaw.contains("conversion") ? .conversion : .clipPublished

            return CoppedRewardTransaction(
                id: stringValue(for: ["id"], in: item) ?? UUID().uuidString.lowercased(),
                kind: kind,
                amountCents: amount,
                amountDisplay: amount.coppedCurrencyDisplay,
                clipID: stringValue(for: ["clip_id", "clipId"], in: item) ?? "",
                orderID: stringValue(for: ["order_id", "orderId"], in: item),
                createdAt: dateValue(for: ["created_at", "createdAt"], in: item) ?? Date()
            )
        }
    }

    private static func parseConversionResponse(from raw: [String: Any]) -> CoppedConversionResponse {
        let reward = dictValue(for: ["reward"], in: raw) ?? [:]
        let balances = dictValue(for: ["balances", "totals"], in: raw) ?? [:]
        let push = dictValue(for: ["push"], in: raw) ?? [:]

        let creditedCents = intValue(
            for: ["credited_cents", "creditedCents", "earnings_added", "reward_cents", "rewardCents"],
            in: raw,
            fallback: reward
        ) ?? 0

        let availableBalanceCents = intValue(
            for: ["available_balance_cents", "availableBalanceCents", "available_cents", "balance_cents", "balanceCents"],
            in: raw,
            fallback: balances
        ) ?? 0

        let pushSent = boolValue(for: ["push_sent", "pushSent", "sent"], in: raw)
            ?? boolValue(for: ["push_sent", "pushSent", "sent"], in: push)
            ?? false

        let withinPushWindow = boolValue(for: ["within_push_window", "withinPushWindow", "within_window", "withinWindow"], in: raw)
            ?? boolValue(for: ["within_push_window", "withinPushWindow", "within_window", "withinWindow"], in: push)
            ?? false

        let success = boolValue(for: ["success", "attributed", "reward_credited", "rewardCredited"], in: raw)
            ?? (creditedCents > 0)

        let creditedDisplay = stringValue(
            for: ["credited_display", "creditedDisplay", "display"],
            in: raw,
            fallback: reward
        ) ?? creditedCents.coppedCurrencyDisplay

        let availableBalanceDisplay = stringValue(
            for: ["available_balance_display", "availableBalanceDisplay", "available_display", "availableDisplay", "balance_display", "balanceDisplay"],
            in: raw,
            fallback: balances
        ) ?? availableBalanceCents.coppedCurrencyDisplay

        return CoppedConversionResponse(
            success: success,
            creditedCents: creditedCents,
            creditedDisplay: creditedDisplay,
            availableBalanceCents: availableBalanceCents,
            availableBalanceDisplay: availableBalanceDisplay,
            pushSent: pushSent,
            withinPushWindow: withinPushWindow
        )
    }

    private static func parseClip(
        from raw: [String: Any],
        fallbackProductId: String,
        apiBaseURL: URL
    ) -> CoppedClip? {
        let clipID = stringValue(for: ["id", "clip_id", "clipId"], in: raw) ?? UUID().uuidString.lowercased()

        let productDict = dictValue(for: ["product"], in: raw)
        let nestedVideo = dictValue(for: ["video"], in: raw)
        let nestedWallet = dictValue(for: ["wallet"], in: raw)
        let nestedOverlay = dictValue(for: ["overlay"], in: raw)
            ?? dictValue(for: ["caption"], in: raw)
            ?? dictValue(for: ["text"], in: raw)

        let productID = stringValue(for: ["product_id", "productId"], in: raw)
            ?? stringValue(for: ["id", "product_id", "productId"], in: productDict ?? [:])
            ?? fallbackProductId

        let videoURL = urlValue(for: ["video_url", "videoURL", "url"], in: raw, apiBaseURL: apiBaseURL)
            ?? urlValue(for: ["url", "video_url", "videoURL"], in: nestedVideo ?? [:], apiBaseURL: apiBaseURL)
            ?? urlValue(for: ["playback_url", "playbackURL"], in: raw, apiBaseURL: apiBaseURL)
        guard let videoURL else { return nil }

        let textOverlay = stringValue(
            for: ["text_overlay", "textOverlay", "caption", "text", "overlay_text", "overlayText"],
            in: raw
        ) ?? stringValue(
            for: ["text_overlay", "textOverlay", "caption", "text", "overlay_text", "overlayText"],
            in: nestedOverlay ?? [:]
        )
        let textPositionRaw = stringValue(for: ["text_position", "textPosition"], in: raw)?.lowercased()
        let textPosition = CoppedTextPosition(rawValue: textPositionRaw ?? "") ?? .bottom

        let durationSeconds = intValue(
            for: ["duration_seconds", "durationSeconds", "duration"],
            in: raw
        ) ?? 10

        let couponCode = stringValue(
            for: ["coupon_code", "couponCode", "wallet_code", "walletCode"],
            in: raw
        ) ?? stringValue(
            for: ["code", "wallet_code", "walletCode"],
            in: nestedWallet ?? [:]
        ) ?? "COP-UNKNOWN"

        let createdAt = dateValue(for: ["created_at", "createdAt"], in: raw) ?? Date()
        let expiresAt = dateValue(for: ["expires_at", "expiresAt"], in: raw)
            ?? createdAt.addingTimeInterval(365 * 24 * 60 * 60)

        return CoppedClip(
            id: clipID,
            receiptID: stringValue(for: ["receipt_id", "receiptId", "order_id", "orderId"], in: raw) ?? "remote-receipt",
            creatorDeviceID: stringValue(for: ["creator_device_id", "creatorDeviceId", "device_id", "deviceId"], in: raw) ?? "remote-device",
            productID: productID,
            videoURL: videoURL,
            textOverlay: textOverlay,
            textPosition: textPosition,
            durationSeconds: max(1, min(120, durationSeconds)),
            couponCode: couponCode,
            couponRedeemed: boolValue(for: ["coupon_redeemed", "couponRedeemed", "redeemed"], in: raw) ?? false,
            conversions: intValue(for: ["conversions", "conversion_count", "conversionCount"], in: raw) ?? 0,
            bonusCouponCode: stringValue(for: ["bonus_coupon_code", "bonusCouponCode"], in: raw),
            bonusPushed: boolValue(for: ["bonus_pushed", "bonusPushed"], in: raw) ?? false,
            bonusRedeemed: boolValue(for: ["bonus_redeemed", "bonusRedeemed"], in: raw) ?? false,
            isActive: boolValue(for: ["is_active", "isActive"], in: raw) ?? true,
            createdAt: createdAt,
            expiresAt: expiresAt
        )
    }

    private static func productIDsFromReceiptPayload(_ payload: [String: Any]) -> [String] {
        if let ids = stringArrayValue(for: ["product_ids", "productIds"], in: payload), !ids.isEmpty {
            return ids
        }

        if let products = arrayValue(for: ["products"], in: payload) {
            let ids = products.compactMap { stringValue(for: ["id", "product_id", "productId"], in: $0) }
            if !ids.isEmpty { return ids }
        }

        if let items = arrayValue(for: ["items", "line_items", "lineItems"], in: payload) {
            let ids = items.compactMap { stringValue(for: ["product_id", "productId", "id"], in: $0) }
            if !ids.isEmpty { return ids }
        }

        return []
    }

    private static func payloadDict(from object: [String: Any]) -> [String: Any] {
        if let data = object["data"] as? [String: Any] {
            return data
        }
        return object
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard !data.isEmpty else { return [:] }
        let json = try JSONSerialization.jsonObject(with: data)
        if let dict = json as? [String: Any] {
            return dict
        }
        if let array = json as? [[String: Any]] {
            return ["items": array]
        }
        return [:]
    }

    private static func urlForPath(_ path: String, apiBaseURL: URL) -> URL {
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return apiBaseURL.appendingPathComponent(trimmed)
    }

    private static func makeURL(from raw: String, apiBaseURL: URL) -> URL? {
        if let absolute = URL(string: raw), absolute.scheme != nil {
            return absolute
        }
        return urlForPath(raw, apiBaseURL: apiBaseURL)
    }

    private nonisolated static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }

        let path = parsed.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty { return parsed }

        var components = URLComponents(url: parsed, resolvingAgainstBaseURL: false)
        components?.path = "/\(path)"
        return components?.url ?? parsed
    }

    private static func value(for keys: [String], in object: [String: Any]) -> Any? {
        for key in keys {
            if let value = object[key] {
                return value
            }
        }
        return nil
    }

    private static func dictValue(for keys: [String], in object: [String: Any]) -> [String: Any]? {
        value(for: keys, in: object) as? [String: Any]
    }

    private static func arrayValue(for keys: [String], in object: [String: Any]) -> [[String: Any]]? {
        guard let raw = value(for: keys, in: object) as? [Any] else { return nil }
        return raw.compactMap { $0 as? [String: Any] }
    }

    private static func stringArrayValue(for keys: [String], in object: [String: Any]) -> [String]? {
        guard let raw = value(for: keys, in: object) as? [Any] else { return nil }
        let values = raw.compactMap { item -> String? in
            if let string = item as? String { return string }
            if let number = item as? NSNumber { return number.stringValue }
            return nil
        }
        return values.isEmpty ? nil : values
    }

    private static func stringValue(
        for keys: [String],
        in object: [String: Any],
        fallback: [String: Any]? = nil
    ) -> String? {
        if let value = value(for: keys, in: object) {
            if let string = value as? String { return string }
            if let number = value as? NSNumber { return number.stringValue }
        }

        if let fallback {
            return stringValue(for: keys, in: fallback)
        }

        return nil
    }

    private static func intValue(
        for keys: [String],
        in object: [String: Any],
        fallback: [String: Any]? = nil
    ) -> Int? {
        if let value = value(for: keys, in: object) {
            if let integer = value as? Int { return integer }
            if let number = value as? NSNumber { return number.intValue }
            if let string = value as? String { return Int(string) }
        }

        if let fallback {
            return intValue(for: keys, in: fallback)
        }

        return nil
    }

    private static func boolValue(for keys: [String], in object: [String: Any]) -> Bool? {
        if let value = value(for: keys, in: object) {
            if let bool = value as? Bool { return bool }
            if let number = value as? NSNumber { return number.boolValue }
            if let string = value as? String {
                switch string.lowercased() {
                case "true", "1", "yes":
                    return true
                case "false", "0", "no":
                    return false
                default:
                    return nil
                }
            }
        }
        return nil
    }

    private static func urlValue(for keys: [String], in object: [String: Any], apiBaseURL: URL) -> URL? {
        guard let raw = stringValue(for: keys, in: object) else { return nil }
        return makeURL(from: raw, apiBaseURL: apiBaseURL)
    }

    private static func dateValue(for keys: [String], in object: [String: Any]) -> Date? {
        guard let raw = value(for: keys, in: object) else { return nil }

        if let timestamp = raw as? TimeInterval {
            return Date(timeIntervalSince1970: timestamp)
        }
        if let number = raw as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        if let string = raw as? String {
            if let seconds = TimeInterval(string) {
                return Date(timeIntervalSince1970: seconds)
            }

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = isoFormatter.date(from: string) {
                return date
            }

            let plainFormatter = ISO8601DateFormatter()
            if let date = plainFormatter.date(from: string) {
                return date
            }
        }

        return nil
    }
}
