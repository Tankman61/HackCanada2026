import PassKit
import SwiftUI
import UIKit

struct CoppedShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum CoppedClipboard {
    @MainActor
    static func copy(_ value: String) {
        UIPasteboard.general.string = value
    }
}

enum CoppedURLLauncher {
    static func isReachable(_ url: URL, timeout: TimeInterval = 2.5) async -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return true
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)

        var headRequest = URLRequest(url: url)
        headRequest.httpMethod = "HEAD"

        do {
            let (_, response) = try await session.data(for: headRequest)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200...399).contains(httpResponse.statusCode)
        } catch {
            var rangeRequest = URLRequest(url: url)
            rangeRequest.httpMethod = "GET"
            rangeRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            do {
                let (_, response) = try await session.data(for: rangeRequest)
                guard let httpResponse = response as? HTTPURLResponse else { return false }
                return (200...399).contains(httpResponse.statusCode)
            } catch {
                return false
            }
        }
    }

    static func isWalletPassURL(_ url: URL, timeout: TimeInterval = 3.0) async -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)

        var headRequest = URLRequest(url: url)
        headRequest.httpMethod = "HEAD"

        if let response = try? await session.data(for: headRequest).1 as? HTTPURLResponse,
           (200...399).contains(response.statusCode),
           looksLikeWalletPass(response) {
            return true
        }

        var rangeRequest = URLRequest(url: url)
        rangeRequest.httpMethod = "GET"
        rangeRequest.setValue("bytes=0-0", forHTTPHeaderField: "Range")

        if let response = try? await session.data(for: rangeRequest).1 as? HTTPURLResponse,
           (200...399).contains(response.statusCode),
           looksLikeWalletPass(response) {
            return true
        }

        return false
    }

    private static func looksLikeWalletPass(_ response: HTTPURLResponse) -> Bool {
        let contentType = headerValue("content-type", in: response)?.lowercased() ?? ""
        let contentDisposition = headerValue("content-disposition", in: response)?.lowercased() ?? ""
        let path = response.url?.path.lowercased() ?? ""

        if contentType.contains("application/vnd.apple.pkpass") || contentType.contains("application/pkpass") {
            return true
        }

        if contentDisposition.contains(".pkpass") || path.hasSuffix(".pkpass") {
            return true
        }

        if contentType.contains("application/octet-stream"),
           path.contains("/wallet/"),
           path.contains("/pass") {
            return true
        }

        return false
    }

    private static func headerValue(_ name: String, in response: HTTPURLResponse) -> String? {
        for (rawKey, rawValue) in response.allHeaderFields {
            guard let key = (rawKey as? String)?.lowercased() else { continue }
            if key == name {
                return rawValue as? String
            }
        }
        return nil
    }

    @MainActor
    static func open(_ url: URL) async -> Bool {
        if shouldRouteInternally(url) {
            NotificationCenter.default.post(name: .clipRouterInvokeURL, object: url.absoluteString)
            return true
        }

        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
    }

    private static func shouldRouteInternally(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let allowedHosts: Set<String> = [
            "clip.copped.app",
            "clipstakes.skilled5041.workers.dev",
        ]
        guard allowedHosts.contains(host) else { return false }

        let path = url.path.lowercased()
        return path.hasPrefix("/v/") || path.hasPrefix("/c/")
    }

    /// Downloads a .pkpass from the given URL and presents the native Add Pass sheet.
    /// Returns a result indicating success, user cancellation, or an error description.
    @MainActor
    static func downloadAndPresentPass(_ url: URL, timeout: TimeInterval = 8.0) async -> WalletPassResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            return .failed("Could not download pass: \(error.localizedDescription)")
        }

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return .failed("Pass endpoint returned HTTP \(http.statusCode).")
        }

        guard !data.isEmpty else {
            return .failed("Pass endpoint returned empty data.")
        }

        let pass: PKPass
        do {
            pass = try PKPass(data: data)
        } catch {
            return .failed("Invalid pass: \(error.localizedDescription)")
        }

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return .failed("No window to present pass.")
        }

        // Find the topmost presented VC
        var presenter = rootVC
        while let next = presenter.presentedViewController { presenter = next }

        let addPassVC = PKAddPassesViewController(pass: pass)
        guard let addPassVC else {
            return .failed("Could not create Add Pass view.")
        }

        return await withCheckedContinuation { continuation in
            addPassVC.delegate = WalletPassDelegateBox(continuation: continuation)
            // Retain the delegate box until dismissed
            objc_setAssociatedObject(addPassVC, &WalletPassDelegateBox.key, addPassVC.delegate, .OBJC_ASSOCIATION_RETAIN)
            presenter.present(addPassVC, animated: true)
        }
    }

    enum WalletPassResult {
        case added
        case dismissed
        case failed(String)
    }
}

private final class WalletPassDelegateBox: NSObject, PKAddPassesViewControllerDelegate {
    static var key: UInt8 = 0
    private let continuation: CheckedContinuation<CoppedURLLauncher.WalletPassResult, Never>
    private var resumed = false

    init(continuation: CheckedContinuation<CoppedURLLauncher.WalletPassResult, Never>) {
        self.continuation = continuation
    }

    func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
        guard !resumed else { return }
        resumed = true
        controller.dismiss(animated: true) {
            // PKAddPassesViewController doesn't tell us if user tapped Add or Cancel,
            // but reaching here means the sheet was presented successfully.
            self.continuation.resume(returning: .added)
        }
    }
}
