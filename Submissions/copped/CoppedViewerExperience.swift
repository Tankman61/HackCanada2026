import AVFoundation
import SwiftUI
import UIKit

struct CoppedViewerExperience: ClipExperience {
    static let urlPattern = "clip.copped.app/v/:productId"
    static let clipName = "Copped Viewer"
    static let clipDescription = "Watch real customer clips and buy in seconds."
    static let teamName = "Copped"
    static let touchpoint: JourneyTouchpoint = .onSite
    static let invocationSource: InvocationSource = .nfcTag
    private static let runtimeInvocationBaseURL = "https://clipstakes.skilled5041.workers.dev"

    let context: ClipContext

    @State private var clips: [CoppedClip] = []
    @State private var isLoading = true
    @State private var selectedClipID: String?
    @State private var showCheckout = false
    @State private var checkoutInFlight = false
    @State private var checkoutOutcome: CoppedCheckoutOutcome?
    @State private var errorMessage: String?
    @State private var copiedReceiptURL = false

    private let deviceID = "copped-device-id"

    private var productID: String {
        let raw = context.pathParameters["productId"] ?? "hoodie"
        return CoppedCatalog.canonicalProductID(raw)
    }

    private var storeDomainOverride: String? {
        context.queryParameters["store"]
    }

    private var apiBaseOverride: String? {
        context.queryParameters["api"] ?? context.queryParameters["api_base"]
    }

    private var apiBaseURL: URL {
        CoppedRemoteBackend.resolveAPIBaseURL(override: apiBaseOverride)
    }

    private var allowMockFallback: Bool {
        guard let raw = context.queryParameters["mock"]?.lowercased() else { return false }
        return raw == "1" || raw == "true" || raw == "yes"
    }

    private var preferredClipID: String? {
        let raw = context.queryParameters["clip"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    private var product: CoppedProduct {
        CoppedCatalog.product(for: productID)
    }

    private var currentClip: CoppedClip? {
        if let selectedClipID,
           let match = clips.first(where: { $0.id == selectedClipID }) {
            return match
        }
        return clips.first
    }

    private var activeClipID: String? {
        selectedClipID ?? clips.first?.id
    }

    var body: some View {
        ZStack {
            CoppedStageBackground()

            if isLoading {
                loadingView
            } else if clips.isEmpty {
                emptyState
            } else {
                reelsFeed
            }

            topHUD
        }
        .onAppear {
            CoppedTheme.bootstrap()
        }
        .task(id: productID + "|" + (storeDomainOverride ?? "") + "|" + (preferredClipID ?? "")) {
            await loadClips()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomOverlay
        }
        .sheet(isPresented: $showCheckout) {
            if currentClip != nil {
                CoppedViewerCheckoutSheet(
                    product: product,
                    isProcessing: checkoutInFlight,
                    onCancel: { showCheckout = false },
                    onConfirm: { Task { await performCheckout() } }
                )
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Reels Feed

    private var reelsFeed: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(clips) { clip in
                        reelPage(for: clip, isActive: clip.id == activeClipID)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .id(clip.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedClipID)
            .onAppear {
                if selectedClipID == nil {
                    selectedClipID = clips.first?.id
                }
            }
        }
        .ignoresSafeArea(edges: [.top, .bottom])
    }

    // MARK: - Top HUD

    private var topHUD: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .font(.custom(Manrope.extraBold, size: 34))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    if !clips.isEmpty {
                        Text("Swipe for more")
                            .font(.custom(Manrope.semiBold, size: 16))
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                Spacer()
            }

            if let errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.custom(Manrope.regular, size: 9))
                    Text(errorMessage)
                        .font(.custom(Manrope.medium, size: 11))
                }
                .foregroundStyle(CoppedPalette.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 86)
        .allowsHitTesting(false)
    }

    // MARK: - Bottom Overlay

    @ViewBuilder
    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            if checkoutOutcome != nil || (!isLoading && !clips.isEmpty) {
                VStack(spacing: 8) {
                    if let outcome = checkoutOutcome {
                        receiptPanel(outcome: outcome)
                    }

                    if !isLoading && !clips.isEmpty {
                        buyBar
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
        }
        .background(
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var buyBar: some View {
        Button {
            showCheckout = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("BUY NOW")
                        .font(.custom(Manrope.extraBold, size: 9))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.7))

                    Text(product.formattedPrice)
                        .font(.custom(Manrope.extraBold, size: 22))
                        .foregroundStyle(.white)

                    Text("Fast checkout")
                        .font(.custom(Manrope.medium, size: 10))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Image(systemName: "cart.badge.plus")
                    .font(.custom(Manrope.bold, size: 26))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(CoppedPalette.accent)
                    .shadow(color: Color.black.opacity(0.3), radius: 10, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(currentClip == nil)
        .opacity(currentClip == nil ? 0.5 : 1)
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.2)

            Text("PULLING LIVE CLIPS")
                .font(.custom(Manrope.extraBold, size: 11))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash.fill")
                .font(.custom(Manrope.bold, size: 34))
                .foregroundStyle(.white.opacity(0.3))

            Text("NO CLIPS YET")
                .font(.custom(Manrope.extraBold, size: 20))
                .foregroundStyle(.white)

            Text("Be first to create social proof for \(product.name).\nStake a 5-15s clip and unlock instant rewards.")
                .font(.custom(Manrope.medium, size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.bottom, 100)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Reel Page

    private func reelPage(for clip: CoppedClip, isActive: Bool) -> some View {
        ZStack {
            CoppedLoopingVideoPlayer(videoURL: clip.videoURL, isActive: isActive)

            if let imageURL = clip.product.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .opacity(0.1)
                            .blur(radius: 8)
                    default:
                        EmptyView()
                    }
                }
                .clipped()
            }

            // Vignette
            LinearGradient(
                colors: [Color.black.opacity(0.4), Color.black.opacity(0.0), Color.black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )

            positionedCaption(for: clip)
                .padding(.horizontal, 14)
                .padding(.top, 120)
                .padding(.bottom, 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func positionedCaption(for clip: CoppedClip) -> some View {
        let text = clip.textOverlay?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            let caption = Text(text.uppercased())
                .font(.custom(Manrope.extraBold, size: 24))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 6)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

            switch clip.textPosition {
            case .top:
                VStack {
                    caption
                    Spacer(minLength: 0)
                }
            case .center:
                VStack {
                    Spacer(minLength: 0)
                    caption
                    Spacer(minLength: 0)
                }
            case .bottom:
                VStack {
                    Spacer(minLength: 0)
                    caption
                }
            }
        } else {
            EmptyView()
        }
    }

    // MARK: - Receipt Panel

    private func receiptPanel(outcome: CoppedCheckoutOutcome) -> some View {
        let creatorURL = URL(string: "\(Self.runtimeInvocationBaseURL)/c/\(outcome.receiptID)")!

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.custom(Manrope.regular, size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("ORDER CONFIRMED")
                        .font(.custom(Manrope.extraBold, size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
            }

            if let conversion = outcome.conversion, conversion.success {
                Text("Someone bought from your reel. You earned \(conversion.creditedDisplay).")
                    .font(.custom(Manrope.bold, size: 11))
                    .foregroundStyle(.white)

                Text("New wallet balance: \(conversion.availableBalanceDisplay)")
                    .font(.custom(Manrope.medium, size: 10))
                    .foregroundStyle(.white.opacity(0.62))
            } else {
                Text("Demo receipt is ready. Open creator flow to record and claim reward.")
                    .font(.custom(Manrope.medium, size: 11))
                    .foregroundStyle(.white.opacity(0.65))
            }

            HStack(spacing: 8) {
                Button("Open Creator") {
                    Task {
                        if await CoppedURLLauncher.open(creatorURL) {
                            return
                        }

                        await MainActor.run {
                            CoppedClipboard.copy(creatorURL.absoluteString)
                            copiedReceiptURL = true
                        }
                    }
                }
                .font(.custom(Manrope.bold, size: 11))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(CoppedPalette.accent, in: RoundedRectangle(cornerRadius: 8))

                Button(copiedReceiptURL ? "Copied Link" : "Copy Link") {
                    Task { @MainActor in
                        CoppedClipboard.copy(creatorURL.absoluteString)
                        copiedReceiptURL = true
                    }
                }
                .font(.custom(Manrope.bold, size: 11))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            }

        }
        .padding(10)
        .coppedGlassCard(cornerRadius: 14)
    }

    // MARK: - Backend

    private func loadClips() async {
        isLoading = true
        errorMessage = nil

        let previousSelectedID = selectedClipID

        _ = await CoppedShopifyPublicCatalogService.shared.loadCatalog(
            storeDomainOverride: storeDomainOverride
        )

        do {
            let queryIDs = CoppedCatalog.queryProductIDs(for: productID)
            var loadedClips: [CoppedClip] = []

            for id in queryIDs {
                loadedClips = try await CoppedRemoteBackend.getClips(
                    productId: id,
                    apiBaseURL: apiBaseURL,
                    deviceID: deviceID
                )
                if !loadedClips.isEmpty {
                    break
                }
            }

            clips = loadedClips
        } catch let error as CoppedRemoteBackendError where error.isConnectivityIssue {
            if allowMockFallback {
                let queryIDs = CoppedCatalog.queryProductIDs(for: productID)
                var loadedClips: [CoppedClip] = []
                for id in queryIDs {
                    loadedClips = await CoppedMockBackend.shared.getClips(productId: id)
                    if !loadedClips.isEmpty {
                        break
                    }
                }
                clips = loadedClips
                errorMessage = "Using local mock clips due to connectivity issue."
            } else {
                clips = []
                errorMessage = "Could not load live clips. Check your connection and try again."
            }
        } catch {
            clips = []
            errorMessage = error.localizedDescription
        }

        let loaded = clips

        if let preferredClipID,
           loaded.contains(where: { $0.id == preferredClipID }) {
            selectedClipID = preferredClipID
        } else if let previousSelectedID,
           loaded.contains(where: { $0.id == previousSelectedID }) {
            selectedClipID = previousSelectedID
        } else {
            selectedClipID = loaded.first?.id
        }

        isLoading = false
    }

    private func performCheckout() async {
        guard let currentClip else { return }

        checkoutInFlight = true
        defer { checkoutInFlight = false }

        do {
            let outcome = try await performCheckoutViaProvider(
                productId: productID,
                clipId: currentClip.id
            )

            await MainActor.run {
                checkoutOutcome = outcome
                copiedReceiptURL = false
                showCheckout = false
            }

            await loadClips()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showCheckout = false
            }
        }
    }

    private func performCheckoutViaProvider(
        productId: String,
        clipId: String?
    ) async throws -> CoppedCheckoutOutcome {
        do {
            let backendProductID = CoppedCatalog.backendCompatibleProductID(productId)
            return try await CoppedRemoteBackend.performCheckout(
                productId: backendProductID,
                clipId: clipId,
                apiBaseURL: apiBaseURL,
                deviceID: deviceID
            )
        } catch let error as CoppedRemoteBackendError where error.isConnectivityIssue {
            guard allowMockFallback else { throw error }
            return try await CoppedMockBackend.shared.performViewerCheckout(
                productId: productId,
                clipId: clipId
            )
        } catch let error as CoppedRemoteBackendError {
            if allowMockFallback, case .requestFailed(let statusCode, _) = error, statusCode == 404 {
                return try await CoppedMockBackend.shared.performViewerCheckout(
                    productId: productId,
                    clipId: clipId
                )
            }
            throw error
        }
    }
}

// MARK: - Checkout Sheet

private struct CoppedViewerCheckoutSheet: View {
    let product: CoppedProduct
    let isProcessing: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                CoppedPalette.ink.ignoresSafeArea()

                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        Image(systemName: "creditcard.fill")
                            .font(.custom(Manrope.light, size: 28))
                            .foregroundStyle(.white.opacity(0.6))

                        Text("CHECKOUT")
                            .font(.custom(Manrope.extraBold, size: 20))
                            .foregroundStyle(.white)

                        Text("Simulated checkout for this demo build")
                            .font(.custom(Manrope.medium, size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                            .multilineTextAlignment(.center)
                    }

                    VStack(spacing: 1) {
                        checkoutRow(label: "Product", value: product.name)
                        checkoutRow(label: "Price", value: product.formattedPrice)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )

                    Spacer(minLength: 4)

                    if isProcessing {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                            Text("Processing simulated checkout...")
                                .font(.custom(Manrope.medium, size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }

                    HStack(spacing: 10) {
                        Button("Cancel", action: onCancel)
                            .buttonStyle(CoppedSecondaryButtonStyle())

                        Button("Pay Now", action: onConfirm)
                            .buttonStyle(CoppedPrimaryButtonStyle(disabled: isProcessing))
                            .disabled(isProcessing)
                    }
                }
                .padding(18)
            }
        }
    }

    private func checkoutRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.custom(Manrope.medium, size: 12))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.custom(Manrope.bold, size: 12))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.04))
    }
}

// MARK: - Video Playback

private struct CoppedLoopingVideoPlayer: View {
    let videoURL: URL
    let isActive: Bool

    @StateObject private var controller = CoppedLoopingVideoController()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.9), Color.black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )

            CoppedPlayerLayerView(player: controller.player)
                .opacity(controller.isReady ? 1 : 0)

            if !controller.isReady {
                VStack(spacing: 8) {
                    if controller.didFail {
                        Image(systemName: "video.slash.fill")
                            .font(.custom(Manrope.semiBold, size: 26))
                            .foregroundStyle(.white.opacity(0.55))
                        Text("Video unavailable")
                            .font(.custom(Manrope.bold, size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        ProgressView()
                            .tint(.white)
                        Text("Loading clip")
                            .font(.custom(Manrope.medium, size: 11))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear {
            controller.configure(with: videoURL)
            controller.setActive(isActive)
        }
        .onChange(of: videoURL) { _, newURL in
            controller.configure(with: newURL)
            controller.setActive(isActive)
        }
        .onChange(of: isActive) { _, active in
            controller.setActive(active)
        }
        .onDisappear {
            controller.setActive(false)
        }
    }
}

@MainActor
private final class CoppedLoopingVideoController: ObservableObject {
    let player = AVPlayer()

    @Published var isReady = false
    @Published var didFail = false

    private static let playbackLoadTimeoutSeconds: UInt64 = 20
    private var configuredURL: URL?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var loadTimeoutTask: Task<Void, Never>?
    private var isActive = false

    init() {
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .none
    }

    func configure(with videoURL: URL) {
        guard configuredURL != videoURL else { return }
        configuredURL = videoURL
        isReady = false
        didFail = false

        loadTimeoutTask?.cancel()
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)

        let item = AVPlayerItem(url: videoURL)
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self else { return }
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self.isReady = true
                    self.didFail = false
                    self.loadTimeoutTask?.cancel()
                    self.loadTimeoutTask = nil
                    if self.isActive {
                        self.player.play()
                    }
                case .failed:
                    self.isReady = false
                    self.didFail = true
                    self.loadTimeoutTask?.cancel()
                    self.loadTimeoutTask = nil
                default:
                    break
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.player.seek(to: .zero)
                if self.isActive {
                    self.player.play()
                }
            }
        }
        player.replaceCurrentItem(with: item)
        loadTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.playbackLoadTimeoutSeconds * 1_000_000_000)
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard !self.isReady else { return }
            self.didFail = true
        }
    }

    func setActive(_ active: Bool) {
        isActive = active
        if active, isReady {
            player.play()
        } else {
            player.pause()
        }
    }

    deinit {
        loadTimeoutTask?.cancel()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }
}

private struct CoppedPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> CoppedPlayerContainerView {
        let view = CoppedPlayerContainerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: CoppedPlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class CoppedPlayerContainerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
