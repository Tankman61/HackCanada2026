import Foundation

enum NFCInvocationScanner {
    private static let invocationHosts = [
        "clip.copped.app",
        "clipstakes.skilled5041.workers.dev",
    ]

    static func normalizeInvocationURL(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("copped:") {
            let payload = String(trimmed.dropFirst("copped:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizeInvocationURL(from: payload)
        }

        if trimmed.contains("://") {
            return trimmed
        }

        if isInvocationURLWithoutScheme(trimmed) {
            return trimmed
        }

        if let productID = extractProductID(from: trimmed) {
            let encoded = productID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? productID
            return "clip.copped.app/v/\(encoded)"
        }

        return nil
    }

    private static func extractProductID(from rawValue: String) -> String? {
        if let queryID = extractQueryValue(named: "productid", from: rawValue) {
            return queryID
        }
        if let queryID = extractQueryValue(named: "product_id", from: rawValue) {
            return queryID
        }
        if let queryID = extractQueryValue(named: "product", from: rawValue) {
            return queryID
        }

        if rawValue.hasPrefix("prod_") {
            return rawValue
        }

        if isSimpleIdentifier(rawValue) {
            return rawValue
        }

        return nil
    }

    private static func extractQueryValue(named name: String, from rawValue: String) -> String? {
        let separatorSet = CharacterSet(charactersIn: "?&")
        let tokens = rawValue.components(separatedBy: separatorSet)

        for token in tokens {
            let parts = token.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            if parts[0].lowercased() == name {
                return parts[1].removingPercentEncoding ?? parts[1]
            }
        }

        return nil
    }

    private static func isSimpleIdentifier(_ value: String) -> Bool {
        guard value.count <= 80 else { return false }
        let invalid = CharacterSet(charactersIn: " /?&=#")
        return value.rangeOfCharacter(from: invalid) == nil
    }

    private static func isInvocationURLWithoutScheme(_ value: String) -> Bool {
        let lowered = value.lowercased()

        if value.hasPrefix("/v/") || value.hasPrefix("/c/") {
            return true
        }

        for host in invocationHosts {
            let withSlash = "\(host)/"
            if lowered.hasPrefix(withSlash) {
                return true
            }
        }

        return false
    }
}
