import SwiftUI
import UIKit

struct CoppedCreatorExperience: ClipExperience {
    static let urlPattern = "clip.copped.app/c/:receiptId"
    static let clipName = "Copped Creator"
    static let clipDescription = "Create a clip, get $5 now, and grow wallet balance on every conversion."
    static let teamName = "Copped"
    static let touchpoint: JourneyTouchpoint = .purchase
    static let invocationSource: InvocationSource = .qrCode
    private static let runtimeInvocationBaseURL = "https://clipstakes.skilled5041.workers.dev"

    enum CreatorStep {
        case loading
        case selectProduct
        case record
        case aiValidating
        case addText
        case confirm
        case success
        case blocked
        case failure
    }

    let context: ClipContext

    @State private var step: CreatorStep = .loading
    @State private var products: [CoppedProduct] = []
    @State private var selectedProduct: CoppedProduct?
    @State private var recordedVideo: CoppedRecordedVideo?
    @State private var textOverlay = ""
    @State private var textPosition: CoppedTextPosition = .bottom
    @State private var effectConfig = CoppedVideoEffectConfig.rioDefault
    @State private var validationMessage = ""
    @State private var isUploading = false
    @State private var reward: CoppedCreateClipResponse?
    @State private var rewardsSnapshot: CoppedRewardsSnapshot?

    @State private var walletAdded = false
    @State private var showShareSheet = false
    @State private var copiedWalletCode = false

    @State private var errorMessage: String?
    @State private var walletStatusMessage: String?
    @State private var blockedStatusMessage: String?

    @State private var pulseHero = false
    @State private var pulseReward = false
    @State private var demoAliasReceiptID = CoppedCreatorExperience.makeDemoAliasReceiptID()

    private let deviceID = "copped-device-id"

    private enum CreatorUploadError: LocalizedError {
        case remoteUploadFailed

        var errorDescription: String? {
            switch self {
            case .remoteUploadFailed:
                return "Video upload to backend failed. Check network/backend and try again."
            }
        }
    }

    private var receiptID: String {
        let raw = context.pathParameters["receiptId"] ?? "order_demo_hoodie"
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "order_demo_hoodie" }
        if trimmed.caseInsensitiveCompare("demo") == .orderedSame {
            return demoAliasReceiptID
        }
        return trimmed
    }

    private var isDemoReceipt: Bool {
        receiptID.hasPrefix("order_demo_")
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

    private var preferredProductIDFromQuery: String? {
        let raw = context.queryParameters["product"]
            ?? context.queryParameters["product_id"]
            ?? context.queryParameters["productId"]
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return CoppedCatalog.canonicalProductID(trimmed)
    }

    private var allowMockFallback: Bool {
        guard let raw = context.queryParameters["mock"]?.lowercased() else { return false }
        return raw == "1" || raw == "true" || raw == "yes"
    }

    private var firstProductIDForViewer: String {
        if let first = products.first?.id {
            return CoppedCatalog.canonicalProductID(first)
        }

        let receiptLower = receiptID.lowercased()
        if receiptLower.contains("hoodie") {
            return "hoodie"
        }
        if receiptLower.contains("book") || receiptLower.contains("vinyl") {
            return "book"
        }
        if receiptLower.contains("food") || receiptLower.contains("hat") || receiptLower.contains("poster") {
            return "food"
        }
        return "hoodie"
    }

    private var trimmedTextOverlay: String {
        textOverlay.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var frontendEffectConfig: CoppedVideoEffectConfig {
        CoppedVideoEffectConfig(look: effectConfig.look, sticker: .none)
    }

    private var showsInlineErrorBanner: Bool {
        guard errorMessage != nil else { return false }
        switch step {
        case .record, .addText, .confirm, .success:
            return true
        case .loading, .selectProduct, .aiValidating, .blocked, .failure:
            return false
        }
    }

    private var stepTimeline: [(CreatorStep, String)] {
        [
            (.selectProduct, "Product"),
            (.record, "Record"),
            (.aiValidating, "AI"),
            (.addText, "Text"),
            (.confirm, "Stake"),
            (.success, "Reward"),
        ]
    }

    private var progressValue: Double {
        let total = Double(stepTimeline.count)
        let progress = Double(max(0, min(stepTimeline.count, stepOrder(step) - 1)))
        return total == 0 ? 0 : progress / total
    }

    var body: some View {
        ZStack {
            CoppedStageBackground()

            ScrollView {
                VStack(spacing: 12) {
                    compactHeader

                    content

                    if showsInlineErrorBanner, let errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.custom(Manrope.regular, size: 11))
                            Text(errorMessage)
                                .font(.custom(Manrope.medium, size: 12))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            CoppedTheme.bootstrap()
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulseHero = true
                pulseReward = true
            }
        }
        .task(id: receiptID + "|" + (storeDomainOverride ?? "")) {
            await loadReceipt()
        }
        .sheet(isPresented: $showShareSheet) {
            CoppedShareSheet(items: shareItems)
        }
    }

    // MARK: - Compact Header (replaces old giant hero)

    private var compactHeader: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "camera.aperture")
                    .font(.custom(Manrope.bold, size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                Text("CREATOR")
                    .font(.custom(Manrope.extraBold, size: 10))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white)
                        .frame(width: max(8, geometry.size.width * progressValue))
                }
            }
            .frame(height: 4)
            .animation(.easeInOut(duration: 0.4), value: progressValue)

            if let rewardsSnapshot {
                HStack {
                    Text("Wallet \(rewardsSnapshot.availableBalanceDisplay)")
                        .font(.custom(Manrope.bold, size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .coppedGlassCard(cornerRadius: 16)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .loading:
            loadingState
        case .selectProduct:
            productSelection
        case .record:
            recordingStep
        case .aiValidating:
            validatingStep
        case .addText:
            addTextStep
        case .confirm:
            confirmStep
        case .success:
            successStep
        case .blocked:
            blockedState
        case .failure:
            failureState
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 6)
                    .frame(width: 56, height: 56)
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(pulseHero ? 240 : -30))
            }

            Text("SYNCING RECEIPT")
                .font(.custom(Manrope.extraBold, size: 11))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.7))

            Text("Checking eligible products")
                .font(.custom(Manrope.medium, size: 11))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .coppedGlassCard(cornerRadius: 18)
    }

    // MARK: - Product Selection

    private var productSelection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Select a product")
                    .font(.custom(Manrope.bold, size: 15))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(products.count) eligible")
                    .font(.custom(Manrope.bold, size: 10))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.1), in: Capsule())
            }
            .padding(.horizontal, 4)

            if products.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox")
                        .font(.custom(Manrope.regular, size: 28))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No eligible products found.")
                        .font(.custom(Manrope.medium, size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .coppedGlassCard(cornerRadius: 14)
            }

            ForEach(products.indices, id: \.self) { index in
                productSelectionRow(products[index])
            }
        }
    }

    private func productSelectionRow(_ product: CoppedProduct) -> some View {
        Button {
            beginRecording(for: product)
        } label: {
            HStack(spacing: 12) {
                productThumb(product)

                VStack(alignment: .leading, spacing: 3) {
                    Text(product.name)
                        .font(.custom(Manrope.bold, size: 15))
                        .foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Text(product.formattedPrice)
                            .font(.custom(Manrope.bold, size: 12))
                            .foregroundStyle(.white)
                        Text("STAKE-READY")
                            .font(.custom(Manrope.extraBold, size: 9))
                            .tracking(0.6)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(productAccent(product), in: Capsule())
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.custom(Manrope.semiBold, size: 13))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(12)
            .coppedGlassCard(cornerRadius: 14)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func beginRecording(for product: CoppedProduct) {
        selectedProduct = product
        recordedVideo = nil
        textOverlay = ""
        textPosition = .bottom
        effectConfig = .rioDefault
        step = .record
    }

    // MARK: - Recording

    private var recordingStep: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                if let selectedProduct {
                    productThumb(selectedProduct)
                        .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Recording")
                            .font(.custom(Manrope.medium, size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(selectedProduct.name)
                            .font(.custom(Manrope.bold, size: 13))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button("Change Product") {
                    step = .selectProduct
                }
                .font(.custom(Manrope.bold, size: 11))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.14), in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .coppedGlassCard(cornerRadius: 12)

            CoppedVideoRecorder(
                minDuration: 5,
                maxDuration: 15,
                effectConfig: $effectConfig
            ) { result in
                recordedVideo = result
                step = .aiValidating
                Task { await runValidation() }
            }
            .coppedGlassCard(cornerRadius: 18)

            HStack(spacing: 8) {
                Text("Record one clean take, then tap Stop.")
                    .font(.custom(Manrope.medium, size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
            }
            .padding(.horizontal, 2)

            if recordedVideo != nil {
                Button("Use Last Recording") {
                    step = .aiValidating
                    Task { await runValidation() }
                }
                .buttonStyle(CoppedPrimaryButtonStyle())
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - Validating

    private var validatingStep: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 6)
                    .frame(width: 56, height: 56)
                Circle()
                    .trim(from: 0, to: 0.6)
                    .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(pulseHero ? 210 : -70))
                Image(systemName: "brain")
                    .font(.custom(Manrope.semiBold, size: 18))
                    .foregroundStyle(.white.opacity(0.7))
            }

            Text("AI REVIEW")
                .font(.custom(Manrope.extraBold, size: 11))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.8))

            Text(validationMessage.isEmpty ? "Checking visibility, framing, and content" : validationMessage)
                .font(.custom(Manrope.medium, size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .coppedGlassCard(cornerRadius: 18)
    }

    // MARK: - Add Text

    private var addTextStep: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Add overlay text")
                    .font(.custom(Manrope.bold, size: 16))
                    .foregroundStyle(.white)
                Spacer()
                Text("Optional")
                    .font(.custom(Manrope.medium, size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }

            VStack(spacing: 10) {
                TextField("OBSESSED", text: $textOverlay)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.custom(Manrope.bold, size: 15))
                    .foregroundStyle(.white)
                    .padding(11)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )

                HStack(spacing: 6) {
                    ForEach(CoppedTextPosition.allCases) { position in
                        Button {
                            textPosition = position
                        } label: {
                            Text(position.rawValue.capitalized)
                                .font(.custom(Manrope.semiBold, size: 12))
                                .foregroundStyle(textPosition == position ? .white : .white.opacity(0.4))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    textPosition == position
                                        ? Color.white.opacity(0.15)
                                        : Color.white.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                textPreviewCard
            }

            HStack(spacing: 8) {
                Button("Back") {
                    withAnimation(.easeOut(duration: 0.2)) { step = .record }
                }
                .buttonStyle(CoppedSecondaryButtonStyle())

                Button("Continue") {
                    withAnimation(.easeOut(duration: 0.25)) { step = .confirm }
                }
                .buttonStyle(CoppedPrimaryButtonStyle())
            }
        }
        .padding(14)
        .coppedGlassCard(cornerRadius: 18)
    }

    private var textPreviewCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.06))
                .frame(height: 110)

            VStack {
                switch textPosition {
                case .top:
                    overlayPreviewText
                    Spacer(minLength: 0)
                case .center:
                    Spacer(minLength: 0)
                    overlayPreviewText
                    Spacer(minLength: 0)
                case .bottom:
                    Spacer(minLength: 0)
                    overlayPreviewText
                }
            }
            .padding(10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var overlayPreviewText: some View {
        Text(trimmedTextOverlay.isEmpty ? "YOUR OVERLAY" : trimmedTextOverlay.uppercased())
            .font(.custom(Manrope.extraBold, size: 15))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 4)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Confirm

    private var confirmStep: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Final Review")
                    .font(.custom(Manrope.bold, size: 17))
                    .foregroundStyle(.white)
                Spacer()
            }

            VStack(spacing: 1) {
                confirmRow(label: "Product", value: selectedProduct?.name ?? "-")
                confirmRow(label: "Duration", value: "\(recordedVideo?.durationSeconds ?? 0)s")
                confirmRow(label: "Look", value: effectConfig.look.displayName)
                confirmRow(label: "Overlay", value: trimmedTextOverlay.isEmpty ? "None" : trimmedTextOverlay)
                confirmRow(label: "Position", value: textPosition.rawValue.capitalized)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Reward preview
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("INSTANT REWARD")
                        .font(.custom(Manrope.extraBold, size: 9))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("$5 Coupon")
                        .font(.custom(Manrope.extraBold, size: 20))
                        .foregroundStyle(.white)
                }
                Spacer()
                Image(systemName: "ticket.fill")
                    .font(.custom(Manrope.bold, size: 24))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(12)
            .background(
                Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )

            if isUploading {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.8)
                    Text("Uploading + minting reward...")
                        .font(.custom(Manrope.medium, size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: 8) {
                Button("Back") {
                    withAnimation(.easeOut(duration: 0.2)) { step = .addText }
                }
                .buttonStyle(CoppedSecondaryButtonStyle())
                .disabled(isUploading)

                Button("Stake Clip") {
                    Task { await uploadAndStake() }
                }
                .buttonStyle(CoppedPrimaryButtonStyle(disabled: isUploading))
                .disabled(isUploading)
            }
        }
        .padding(14)
        .coppedGlassCard(cornerRadius: 18)
    }

    // MARK: - Success

    private var successStep: some View {
        VStack(spacing: 14) {
            if let reward {
                let displayedBalance = rewardsSnapshot?.availableBalanceDisplay ?? reward.availableBalanceDisplay
                let walletCode = rewardsSnapshot?.walletCode ?? reward.walletCode
                let passURL = rewardsSnapshot?.passURL ?? reward.passURL
                let transactions = rewardsSnapshot?.transactions ?? []

                // Header
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.custom(Manrope.bold, size: 32))
                        .foregroundStyle(.white)

                    Text("CLIP IS LIVE")
                        .font(.custom(Manrope.extraBold, size: 10))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.6))
                }

                // Reward card
                VStack(spacing: 10) {
                    Text("+\(reward.instantCreditDisplay)")
                        .font(.custom(Manrope.extraBold, size: 44))
                        .foregroundStyle(.white)

                    Text("ADDED TO YOUR WALLET BALANCE")
                        .font(.custom(Manrope.extraBold, size: 9))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.8))

                    HStack(spacing: 8) {
                        Text(displayedBalance)
                            .font(.custom(Manrope.bold, size: 14))
                            .foregroundStyle(.white)

                        Button(copiedWalletCode ? "Copied" : "Copy Wallet Code") {
                            Task { @MainActor in
                                CoppedClipboard.copy(walletCode)
                                copiedWalletCode = true
                            }
                        }
                        .font(.custom(Manrope.bold, size: 11))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.15), in: Capsule())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(
                    Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 18)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )

                // Actions
                VStack(spacing: 8) {
                    Button {
                        Task { @MainActor in
                            let fallbackPassURL = CoppedRemoteBackend.fallbackWalletPassURL(
                                apiBaseURL: apiBaseURL,
                                walletCode: walletCode
                            )

                            // Try primary pass URL first
                            let primaryResult = await CoppedURLLauncher.downloadAndPresentPass(passURL)
                            switch primaryResult {
                            case .added, .dismissed:
                                walletAdded = true
                                walletStatusMessage = "Wallet pass added."
                                return
                            case .failed:
                                break
                            }

                            // Try fallback URL if different
                            if passURL != fallbackPassURL {
                                let fallbackResult = await CoppedURLLauncher.downloadAndPresentPass(fallbackPassURL)
                                switch fallbackResult {
                                case .added, .dismissed:
                                    walletAdded = true
                                    walletStatusMessage = "Wallet pass added."
                                    return
                                case .failed:
                                    break
                                }
                            }

                            CoppedClipboard.copy(walletCode)
                            walletStatusMessage = "Wallet pass unavailable. Wallet code copied."
                        }
                    } label: {
                        Label(
                            walletAdded ? "Wallet Pass Added" : "Add to Apple Wallet",
                            systemImage: walletAdded ? "checkmark.circle.fill" : "wallet.pass"
                        )
                    }
                    .buttonStyle(CoppedPrimaryButtonStyle())

                    Button {
                        Task { await openViewerForSuccess(clipID: reward.clipID) }
                    } label: {
                        Label("Watch My Clip", systemImage: "play.rectangle.fill")
                    }
                    .buttonStyle(CoppedSecondaryButtonStyle())

                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Share to Stories", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(CoppedSecondaryButtonStyle())
                }

                if let walletStatusMessage {
                    Text(walletStatusMessage)
                        .font(.custom(Manrope.medium, size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }

                if !transactions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Earnings")
                            .font(.custom(Manrope.bold, size: 12))
                            .foregroundStyle(.white.opacity(0.82))

                        ForEach(transactions.prefix(3)) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.kind == .conversion ? "cart.fill.badge.plus" : "video.badge.plus")
                                    .font(.custom(Manrope.bold, size: 11))
                                    .foregroundStyle(.white)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.kind == .conversion ? "Someone bought from your reel" : "Clip published")
                                        .font(.custom(Manrope.medium, size: 11))
                                        .foregroundStyle(.white.opacity(0.82))
                                    if item.kind == .conversion {
                                        Text("You earned \(item.amountDisplay)")
                                            .font(.custom(Manrope.medium, size: 10))
                                            .foregroundStyle(.white.opacity(0.55))
                                    }
                                }
                                Spacer()
                                Text("+\(item.amountDisplay)")
                                    .font(.custom(Manrope.bold, size: 11))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .coppedGlassCard(cornerRadius: 12)
                }
            }
        }
        .padding(14)
        .coppedGlassCard(cornerRadius: 18)
    }

    // MARK: - Blocked / Failure

    private var blockedState: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.custom(Manrope.bold, size: 36))
                .foregroundStyle(.white.opacity(0.7))

            Text("Receipt Already Used")
                .font(.custom(Manrope.bold, size: 18))
                .foregroundStyle(.white)

            Text(errorMessage ?? "This receipt already created a clip.")
                .font(.custom(Manrope.medium, size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            if let rewardsSnapshot {
                Text("Wallet balance: \(rewardsSnapshot.availableBalanceDisplay)")
                    .font(.custom(Manrope.bold, size: 12))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 8) {
                Button("View Existing Clips") {
                    Task { await openViewerForBlockedReceipt() }
                }
                .buttonStyle(CoppedPrimaryButtonStyle())

                if receiptID.hasPrefix("order_demo_") {
                    Button("Use Fresh Demo Receipt") {
                        Task { await openFreshDemoReceipt() }
                    }
                    .buttonStyle(CoppedSecondaryButtonStyle())
                }
            }
            .padding(.horizontal, 18)

            if let blockedStatusMessage {
                Text(blockedStatusMessage)
                    .font(.custom(Manrope.medium, size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .coppedGlassCard(cornerRadius: 18)
    }

    private var failureState: some View {
        VStack(spacing: 10) {
            Image(systemName: "xmark.octagon.fill")
                .font(.custom(Manrope.bold, size: 36))
                .foregroundStyle(.white.opacity(0.5))

            Text("Could Not Load Receipt")
                .font(.custom(Manrope.bold, size: 18))
                .foregroundStyle(.white)

            Text(errorMessage ?? "Try another receipt URL.")
                .font(.custom(Manrope.medium, size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            Button("Retry") {
                Task { await loadReceipt() }
            }
            .buttonStyle(CoppedPrimaryButtonStyle())
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 14)
        .coppedGlassCard(cornerRadius: 18)
    }

    // MARK: - Helpers

    private func confirmRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.custom(Manrope.medium, size: 12))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.custom(Manrope.bold, size: 12))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04))
    }

    private func productThumb(_ product: CoppedProduct) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))

            if let imageURL = product.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: product.systemImage)
                            .font(.custom(Manrope.semiBold, size: 14))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            } else {
                Image(systemName: product.systemImage)
                    .font(.custom(Manrope.semiBold, size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func productAccent(_ product: CoppedProduct) -> Color {
        .white.opacity(0.15)
    }

    private func stepOrder(_ value: CreatorStep) -> Int {
        switch value {
        case .loading: return 0
        case .selectProduct: return 1
        case .record: return 2
        case .aiValidating: return 3
        case .addText: return 4
        case .confirm: return 5
        case .success: return 6
        case .blocked: return 7
        case .failure: return 8
        }
    }

    private var shareItems: [Any] {
        guard let reward else {
            return ["I created a Copped video and unlocked rewards."]
        }

        return [
            "I just staked a clip on COPPED and grew my wallet balance.",
            "Wallet code: \(reward.walletCode)"
        ]
    }

    // MARK: - Backend

    private func loadReceipt() async {
        await MainActor.run {
            step = .loading
            errorMessage = nil
            blockedStatusMessage = nil
        }

        await refreshRewards()

        _ = await CoppedShopifyPublicCatalogService.shared.loadCatalog(
            storeDomainOverride: storeDomainOverride
        )

        do {
            let receipt = try await getReceipt()
            await MainActor.run {
                products = receipt.products
                if let preferredID = preferredProductIDFromQuery,
                   let preferred = receipt.products.first(where: {
                       CoppedCatalog.canonicalProductID($0.id) == preferredID
                   }) {
                    beginRecording(for: preferred)
                } else {
                    step = .selectProduct
                }
            }
        } catch {
            let fallbackProducts = await productsForUsedReceipt()
            await MainActor.run {
                errorMessage = error.localizedDescription
                if let backendError = error as? CoppedBackendError, backendError == .receiptAlreadyUsed {
                    if !fallbackProducts.isEmpty {
                        products = fallbackProducts
                    }
                    step = .blocked
                } else {
                    step = .failure
                }
            }
        }
    }

    private func runValidation() async {
        guard let recordedVideo else {
            await MainActor.run {
                errorMessage = "Record a clip before validation."
                step = .record
            }
            return
        }

        await MainActor.run {
            validationMessage = ""
        }

        let result = await CoppedAIValidator.validate(
            videoURL: recordedVideo.fileURL,
            expectedProductId: selectedProduct?.id ?? "",
            durationSeconds: recordedVideo.durationSeconds
        )

        try? await Task.sleep(nanoseconds: 450_000_000)

        await MainActor.run {
            validationMessage = result.message
            if result.isValid {
                step = .addText
                errorMessage = nil
            } else {
                errorMessage = result.message
                step = .record
            }
        }
    }

    private func uploadAndStake() async {
        guard let selectedProduct, let recordedVideo else { return }

        await MainActor.run {
            isUploading = true
            errorMessage = nil
        }

        defer {
            Task { @MainActor in
                isUploading = false
            }
        }

        do {
            let backendProductID = CoppedCatalog.backendCompatibleProductID(selectedProduct.id)
            let uploadResult = try await createUploadURL(productId: backendProductID)
            let upload = uploadResult.response

            var preparedVideoURL = recordedVideo.fileURL
            if let sourceURL = preparedVideoURL {
                let compositedURL = await CoppedVideoCompositor.renderForUpload(
                    to: sourceURL,
                    text: trimmedTextOverlay,
                    position: textPosition,
                    effectConfig: frontendEffectConfig
                )
                preparedVideoURL = compositedURL ?? sourceURL
            }

            let publishedVideo = await CoppedVideoStorage.shared.publishVideo(
                sourceURL: preparedVideoURL,
                upload: upload
            )

            if publishedVideo.usedLocalFallback && !allowMockFallback {
                throw CreatorUploadError.remoteUploadFailed
            }

            var didBakeVisualOverlays = false
            if let originalURL = recordedVideo.fileURL, let preparedVideoURL {
                didBakeVisualOverlays = preparedVideoURL != originalURL
            }

            var clipMetadataTextOverlay: String? = trimmedTextOverlay.isEmpty ? nil : trimmedTextOverlay
            if didBakeVisualOverlays {
                // Text has already been burned into exported media, avoid duplicate runtime caption in viewer.
                clipMetadataTextOverlay = nil
            }

            let createClipResult = try await createClip(
                receiptId: receiptID,
                deviceID: deviceID,
                productId: backendProductID,
                videoURL: publishedVideo.videoURL,
                textOverlay: clipMetadataTextOverlay,
                textPosition: textPosition,
                durationSeconds: recordedVideo.durationSeconds
            )
            let response = createClipResult.response
            let usedConnectivityFallback = uploadResult.usedConnectivityFallback || createClipResult.usedConnectivityFallback

            await MainActor.run {
                reward = response
                copiedWalletCode = false
                walletAdded = false
                if usedConnectivityFallback {
                    walletStatusMessage = "Network issue detected. This reward is from local demo fallback."
                } else if publishedVideo.usedLocalFallback {
                    walletStatusMessage = "Upload fell back locally. Retry on stable network for remote publishing."
                } else {
                    walletStatusMessage = nil
                }
                step = .success
            }

            await refreshRewards()
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                step = .confirm
            }
        }
    }

    private func refreshRewards() async {
        guard let snapshot = await getRewards() else { return }
        await MainActor.run {
            rewardsSnapshot = snapshot
        }
    }

    private func getReceipt() async throws -> CoppedReceipt {
        if receiptID.hasPrefix("order_demo_hoodie_demo_") {
            return await CoppedMockBackend.shared.ensureDemoReceipt(receiptId: receiptID)
        }

        if receiptID.hasPrefix("order_demo_") {
            return try await CoppedMockBackend.shared.getReceipt(receiptId: receiptID)
        }

        do {
            return try await CoppedRemoteBackend.getReceipt(
                receiptId: receiptID,
                apiBaseURL: apiBaseURL,
                deviceID: deviceID
            )
        } catch let error as CoppedBackendError where error == .receiptNotFound {
            if receiptID.hasPrefix("order_demo_") {
                return try await CoppedMockBackend.shared.getReceipt(receiptId: receiptID)
            }
            throw error
        } catch let error as CoppedRemoteBackendError where error.isConnectivityIssue {
            return try await CoppedMockBackend.shared.getReceipt(receiptId: receiptID)
        }
    }

    private func createUploadURL(productId: String) async throws -> (
        response: CoppedUploadURLResponse,
        usedConnectivityFallback: Bool
    ) {
        do {
            return (
                response: try await CoppedRemoteBackend.createUploadURL(
                    receiptId: receiptID,
                    productId: productId,
                    apiBaseURL: apiBaseURL,
                    deviceID: deviceID
                ),
                usedConnectivityFallback: false
            )
        } catch let error as CoppedRemoteBackendError where error.isConnectivityIssue {
            guard isDemoReceipt, allowMockFallback else { throw error }
            return (
                response: await CoppedMockBackend.shared.createUploadURL(
                    receiptId: receiptID,
                    productId: productId
                ),
                usedConnectivityFallback: true
            )
        }
    }

    private func createClip(
        receiptId: String,
        deviceID: String,
        productId: String,
        videoURL: URL,
        textOverlay: String?,
        textPosition: CoppedTextPosition,
        durationSeconds: Int
    ) async throws -> (
        response: CoppedCreateClipResponse,
        usedConnectivityFallback: Bool
    ) {
        do {
            return (
                response: try await CoppedRemoteBackend.createClip(
                    receiptId: receiptId,
                    deviceID: deviceID,
                    productId: productId,
                    videoURL: videoURL,
                    textOverlay: textOverlay,
                    textPosition: textPosition,
                    durationSeconds: durationSeconds,
                    apiBaseURL: apiBaseURL
                ),
                usedConnectivityFallback: false
            )
        } catch let error as CoppedRemoteBackendError where error.isConnectivityIssue {
            guard receiptId.hasPrefix("order_demo_"), allowMockFallback else { throw error }
            return (
                response: try await CoppedMockBackend.shared.createClip(
                    receiptId: receiptId,
                    deviceID: deviceID,
                    productId: productId,
                    videoURL: videoURL,
                    textOverlay: textOverlay,
                    textPosition: textPosition,
                    durationSeconds: durationSeconds
                ),
                usedConnectivityFallback: true
            )
        }
    }

    private func getRewards() async -> CoppedRewardsSnapshot? {
        do {
            return try await CoppedRemoteBackend.getRewards(
                deviceID: deviceID,
                apiBaseURL: apiBaseURL
            )
        } catch let error as CoppedRemoteBackendError where error.isConnectivityIssue {
            return await CoppedMockBackend.shared.getRewards(deviceID: deviceID)
        } catch {
            return nil
        }
    }

    private func productsForUsedReceipt() async -> [CoppedProduct] {
        if receiptID.hasPrefix("order_demo_") {
            if let receipt = try? await CoppedMockBackend.shared.getReceiptIncludingUsed(receiptId: receiptID) {
                return receipt.products
            }
            return []
        }

        if let receipt = try? await CoppedRemoteBackend.getReceipt(
            receiptId: receiptID,
            apiBaseURL: apiBaseURL,
            deviceID: deviceID
        ) {
            return receipt.products
        }

        return []
    }

    @MainActor
    private func viewerLink(for productID: String, clipID: String?) -> URL {
        let canonicalProductID = CoppedCatalog.canonicalProductID(productID)
        var components = URLComponents(string: "\(Self.runtimeInvocationBaseURL)/v/\(canonicalProductID)")!
        if let clipID, !clipID.isEmpty {
            components.queryItems = [URLQueryItem(name: "clip", value: clipID)]
        }
        return components.url!
    }

    @MainActor
    private func creatorDemoLink() -> URL {
        URL(string: "\(Self.runtimeInvocationBaseURL)/c/demo")!
    }

    private func openViewerForBlockedReceipt() async {
        let target = await MainActor.run { viewerLink(for: firstProductIDForViewer, clipID: nil) }
        if await CoppedURLLauncher.open(target) {
            await MainActor.run {
                blockedStatusMessage = "Opened viewer."
            }
            return
        }

        await MainActor.run {
            CoppedClipboard.copy(target.absoluteString)
            blockedStatusMessage = "Could not open clips. Link copied."
        }
    }

    private func openViewerForSuccess(clipID: String) async {
        let productID = selectedProduct?.id ?? firstProductIDForViewer
        let target = await MainActor.run { viewerLink(for: productID, clipID: clipID) }

        if await CoppedURLLauncher.open(target) {
            await MainActor.run {
                walletStatusMessage = "Opened your clip in viewer."
            }
            return
        }

        await MainActor.run {
            CoppedClipboard.copy(target.absoluteString)
            walletStatusMessage = "Could not open clip. Link copied."
        }
    }

    private func openFreshDemoReceipt() async {
        let target = await MainActor.run { creatorDemoLink() }
        if await CoppedURLLauncher.open(target) {
            await MainActor.run {
                blockedStatusMessage = "Opened new demo receipt."
            }
            return
        }

        await MainActor.run {
            CoppedClipboard.copy(target.absoluteString)
            blockedStatusMessage = "Could not open demo link directly. Link copied."
        }
    }

    nonisolated private static func makeDemoAliasReceiptID() -> String {
        let token = String(UUID().uuidString.prefix(8)).lowercased()
        return "order_demo_hoodie_demo_\(token)"
    }
}
