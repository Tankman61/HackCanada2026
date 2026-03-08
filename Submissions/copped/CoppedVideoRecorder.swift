import AVFoundation
internal import Combine
import CoreImage
import SwiftUI
import UIKit

private enum CoppedLiveFXRuntime {
    static let previewEnabled = false
}

struct CoppedVideoRecorder: View {
    let minDuration: TimeInterval
    let maxDuration: TimeInterval
    @Binding var effectConfig: CoppedVideoEffectConfig
    let onRecorded: (CoppedRecordedVideo) -> Void

    @StateObject private var controller = CoppedCameraController()
    @State private var simulatorRecording = false
    @State private var simulatorElapsed: TimeInterval = 0
    @State private var simulatorError: String?

    private let simulatorTicker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    init(
        minDuration: TimeInterval,
        maxDuration: TimeInterval,
        effectConfig: Binding<CoppedVideoEffectConfig>,
        onRecorded: @escaping (CoppedRecordedVideo) -> Void
    ) {
        self.minDuration = minDuration
        self.maxDuration = maxDuration
        _effectConfig = effectConfig
        self.onRecorded = onRecorded
    }

    private var recordingCanvasHeight: CGFloat {
        let screenHeight = UIScreen.main.bounds.height
        return max(250, min(390, screenHeight * 0.42))
    }

    private var effectsLocked: Bool {
        if controller.useSimulatorFallback {
            return simulatorRecording
        }
        return controller.isRecording || controller.isFinalizing
    }

    private var frontendEffectConfig: CoppedVideoEffectConfig {
        CoppedVideoEffectConfig(look: effectConfig.look, sticker: .none)
    }

    var body: some View {
        VStack(spacing: 0) {
            if controller.useSimulatorFallback {
                simulatorBody
            } else {
                cameraBody
            }

            if let message = controller.infoMessage {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.custom(Manrope.regular, size: 10))
                    Text(message)
                        .font(.custom(Manrope.medium, size: 11))
                }
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            if let message = controller.errorMessage ?? simulatorError {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.custom(Manrope.regular, size: 10))
                    Text(message)
                        .font(.custom(Manrope.medium, size: 11))
                }
                .foregroundStyle(CoppedPalette.warning)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(CoppedPalette.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            if effectConfig.sticker != .none {
                effectConfig.sticker = .none
            }
            controller.updateEffectConfig(frontendEffectConfig)
            controller.prepare(minDuration: minDuration, maxDuration: maxDuration, onRecorded: onRecorded)
        }
        .onChange(of: effectConfig) { _, newValue in
            let sanitized = CoppedVideoEffectConfig(look: newValue.look, sticker: .none)
            if newValue.sticker != .none {
                effectConfig = sanitized
            }
            controller.updateEffectConfig(sanitized)
        }
        .onDisappear {
            controller.stopSession()
        }
        .onReceive(simulatorTicker) { _ in
            guard simulatorRecording else { return }
            simulatorElapsed += 0.1
            if simulatorElapsed >= maxDuration {
                stopSimulatorRecording()
            }
        }
    }

    private var cameraBody: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                CoppedCameraPreview(session: controller.session)
                    .frame(maxWidth: .infinity)
                    .frame(height: recordingCanvasHeight)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                if controller.useLiveFXPreview,
                   let previewImage = controller.previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: recordingCanvasHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                LinearGradient(
                    colors: [Color.black.opacity(0.35), Color.clear, Color.black.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))

                HStack(spacing: 8) {
                    recordPill(elapsed: controller.elapsed, mode: .camera)
                    Spacer()
                    if controller.isRecording {
                        Text("REC")
                            .font(.custom(Manrope.extraBold, size: 10))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red, in: Capsule())
                    }
                }
                .padding(12)

                if !controller.isSessionRunning, controller.errorMessage == nil {
                    VStack(spacing: 6) {
                        ProgressView()
                            .tint(.white)
                        Text("Preparing camera...")
                            .font(.custom(Manrope.medium, size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                if controller.isFinalizing {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.black.opacity(0.45))
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Finalizing clip...")
                                .font(.custom(Manrope.semiBold, size: 12))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .padding(.horizontal, 2)

            effectPickerCard

            if controller.isFinalizing {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("Saving your recording")
                        .font(.custom(Manrope.semiBold, size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            } else {
                let canStopRecording = controller.elapsed >= minDuration
                recordButton(
                    isRecording: controller.isRecording,
                    canStop: canStopRecording,
                    remainingSeconds: max(0, Int(ceil(minDuration - controller.elapsed))),
                    onTap: {
                        if controller.isRecording {
                            guard canStopRecording else { return }
                            controller.stopRecording()
                        } else {
                            simulatorError = nil
                            controller.startRecording()
                        }
                    },
                    accentColor: .red
                )
            }

            recorderHint(
                controller.isFinalizing
                    ? "Please wait while the clip is saved."
                    : (controller.isRecording
                        ? "Recording live. Effects are locked until stop."
                        : "Capture a vertical clip (5-15s).")
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private var simulatorBody: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: recordingCanvasHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                VStack(spacing: 8) {
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                        .font(.custom(Manrope.light, size: 30))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Simulator Mode")
                        .font(.custom(Manrope.semiBold, size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Effects preview is static in simulator")
                        .font(.custom(Manrope.medium, size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }

                HStack(spacing: 8) {
                    recordPill(elapsed: simulatorElapsed, mode: .simulator)
                    Spacer()
                    if simulatorRecording {
                        Text("REC")
                            .font(.custom(Manrope.extraBold, size: 10))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red, in: Capsule())
                    }
                }
                .padding(12)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .padding(.horizontal, 2)

            effectPickerCard

            let canStopRecording = simulatorElapsed >= minDuration
            recordButton(
                isRecording: simulatorRecording,
                canStop: canStopRecording,
                remainingSeconds: max(0, Int(ceil(minDuration - simulatorElapsed))),
                onTap: {
                    if simulatorRecording {
                        guard canStopRecording else { return }
                        stopSimulatorRecording()
                    } else {
                        startSimulatorRecording()
                    }
                },
                accentColor: CoppedPalette.accent
            )

            recorderHint(
                simulatorRecording
                    ? "Recording simulated clip. Effects are locked until stop."
                    : "Simulator fallback still enforces 5-15 seconds."
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private var effectPickerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RIO FX PACK")
                .font(.custom(Manrope.extraBold, size: 10))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.62))

            VStack(alignment: .leading, spacing: 7) {
                Text("Look")
                    .font(.custom(Manrope.medium, size: 10))
                    .foregroundStyle(.white.opacity(0.5))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(CoppedVideoLook.allCases) { look in
                            effectChip(
                                title: look.displayName,
                                isSelected: effectConfig.look == look,
                                disabled: effectsLocked
                            ) {
                                effectConfig.look = look
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .coppedGlassCard(cornerRadius: 12)
    }

    private func effectChip(
        title: String,
        isSelected: Bool,
        disabled: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            Text(title)
                .font(.custom(Manrope.bold, size: 11))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.55))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    isSelected
                        ? Color.white.opacity(0.18)
                        : Color.white.opacity(0.05),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(isSelected ? 0.28 : 0.1), lineWidth: 0.5)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1.0)
    }

    private func recordButton(
        isRecording: Bool,
        canStop: Bool,
        remainingSeconds: Int,
        onTap: @escaping () -> Void,
        accentColor: Color
    ) -> some View {
        let stopDisabled = isRecording && !canStop
        let title: String
        if isRecording {
            title = canStop ? "Stop Recording" : "Keep Recording \(remainingSeconds)s"
        } else {
            title = "Start Recording"
        }

        let iconName: String
        if isRecording {
            iconName = canStop ? "stop.fill" : "timer"
        } else {
            iconName = "record.circle.fill"
        }

        return Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.custom(Manrope.extraBold, size: 16))

                Text(title)
                    .font(.custom(Manrope.extraBold, size: 15))
            }
            .foregroundStyle(stopDisabled ? .white.opacity(0.7) : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(stopDisabled ? Color.white.opacity(0.25) : (isRecording ? Color.red : accentColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 8, y: 4)
            .animation(.easeInOut(duration: 0.2), value: isRecording)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(stopDisabled)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }

    private func recorderHint(_ text: String) -> some View {
        Text(text)
            .font(.custom(Manrope.medium, size: 11))
            .foregroundStyle(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.top, 2)
    }

    @ViewBuilder
    private func recordPill(elapsed: TimeInterval, mode: CoppedCaptureMode) -> some View {
        let isActive = (mode == .camera ? controller.isRecording : simulatorRecording)
        HStack(spacing: 5) {
            Circle()
                .fill(isActive ? Color.red : .white.opacity(0.5))
                .frame(width: 6, height: 6)
            Text("\(Int(elapsed))s")
                .font(.custom(Manrope.bold, size: 11))
                .foregroundStyle(.white)
            Text("\(Int(minDuration))-\(Int(maxDuration))s")
                .font(.custom(Manrope.medium, size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func startSimulatorRecording() {
        simulatorError = nil
        simulatorElapsed = 0
        simulatorRecording = true
    }

    private func stopSimulatorRecording() {
        simulatorRecording = false

        if simulatorElapsed < minDuration {
            simulatorError = "Clip must be at least \(Int(minDuration)) seconds."
            return
        }

        let rounded = min(Int(simulatorElapsed.rounded()), Int(maxDuration))
        onRecorded(
            CoppedRecordedVideo(
                fileURL: nil,
                durationSeconds: rounded,
                captureMode: .simulator
            )
        )
    }
}

private struct CoppedStickerPreviewOverlay: View {
    let sticker: CoppedVideoSticker
    let isAnimating: Bool

    @State private var transit: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                switch sticker {
                case .none:
                    EmptyView()

                case .shootingStar:
                    ZStack {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.0),
                                        Color.white.opacity(isAnimating ? 0.24 : 0.12),
                                        Color.white.opacity(0.0),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 110, height: 5)
                            .position(
                                x: (-65 + (proxy.size.width + 130) * transit),
                                y: proxy.size.height * 0.36 - (22 * sin(Double(transit) * .pi))
                            )

                        CoppedShootingStarGlyph()
                            .fill(.white.opacity(isAnimating ? 0.92 : 0.62))
                            .frame(width: 34, height: 34)
                            .shadow(color: .white.opacity(0.5), radius: 7)
                            .position(
                                x: (-40 + (proxy.size.width + 80) * transit),
                                y: proxy.size.height * 0.34 - (24 * sin(Double(transit) * .pi))
                            )
                    }

                case .dolphinSplash:
                    ZStack {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .stroke(Color.white.opacity(0.35), lineWidth: 1.2)
                                .frame(width: CGFloat(18 + (index * 8)), height: CGFloat(18 + (index * 8)))
                                .position(
                                    x: proxy.size.width * 0.55,
                                    y: proxy.size.height * 0.7
                                )
                                .opacity(isAnimating ? (0.2 + (Double(index) * 0.15)) : 0.1)
                        }

                        CoppedDolphinGlyph()
                            .fill(.white.opacity(isAnimating ? 0.9 : 0.65))
                            .frame(width: 64, height: 42)
                            .shadow(color: .white.opacity(0.35), radius: 6)
                            .rotationEffect(.degrees(-8 + (Double(transit) * 14)))
                            .position(
                                x: (-42 + (proxy.size.width + 84) * transit),
                                y: proxy.size.height * 0.7 - (22 * sin(Double(transit) * .pi * 2))
                            )
                    }
                }
            }
            .onAppear {
                startAnimation()
            }
            .onChange(of: sticker) { _, _ in
                restartAnimation()
            }
            .onChange(of: isAnimating) { _, _ in
                restartAnimation()
            }
        }
        .allowsHitTesting(false)
    }

    private func restartAnimation() {
        transit = 0
        startAnimation()
    }

    private func startAnimation() {
        guard sticker != .none else { return }
        guard isAnimating else { return }

        let duration: Double = sticker == .shootingStar ? 1.5 : 2.8
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            transit = 1
        }
    }
}

private struct CoppedDolphinGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let bodyRect = CGRect(
            x: rect.minX + rect.width * 0.2,
            y: rect.minY + rect.height * 0.25,
            width: rect.width * 0.62,
            height: rect.height * 0.5
        )
        path.addEllipse(in: bodyRect)

        var tail = Path()
        tail.move(to: CGPoint(x: bodyRect.maxX - 1, y: bodyRect.midY))
        tail.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.2))
        tail.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - rect.height * 0.2))
        tail.closeSubpath()
        path.addPath(tail)

        var fin = Path()
        fin.move(to: CGPoint(x: bodyRect.midX - 4, y: bodyRect.minY + 2))
        fin.addLine(to: CGPoint(x: bodyRect.midX + 8, y: rect.minY))
        fin.addLine(to: CGPoint(x: bodyRect.midX + 14, y: bodyRect.minY + 9))
        fin.closeSubpath()
        path.addPath(fin)

        return path
    }
}

private struct CoppedShootingStarGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) * 0.5
        let inner = outer * 0.44

        for index in 0..<10 {
            let angle = CGFloat(index) * (.pi / 5) - (.pi / 2)
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(
                x: center.x + (cos(angle) * radius),
                y: center.y + (sin(angle) * radius)
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

final class CoppedCameraController: NSObject, ObservableObject {
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var isSessionRunning = false
    @Published var isRecording = false
    @Published var isFinalizing = false
    @Published var elapsed: TimeInterval = 0
    @Published var useSimulatorFallback = false
    @Published var useLiveFXPreview = false
    @Published var previewImage: UIImage?

    let session = AVCaptureSession()

    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "copped.camera.session")
    private let videoOutputQueue = DispatchQueue(label: "copped.camera.video-output")
    private let ciContext = CIContext(options: [CIContextOption.useSoftwareRenderer: false])

    private var isConfigured = false
    private var minDuration: TimeInterval = 5
    private var maxDuration: TimeInterval = 15
    private var recordingStartDate: Date?
    private var timer: Timer?
    private var onRecorded: ((CoppedRecordedVideo) -> Void)?
    private var effectConfig: CoppedVideoEffectConfig = .rioDefault
    private var lastPreviewTimestamp: Double = 0
    private var didFallbackLiveFX = false

    func prepare(
        minDuration: TimeInterval,
        maxDuration: TimeInterval,
        onRecorded: @escaping (CoppedRecordedVideo) -> Void
    ) {
        self.minDuration = minDuration
        self.maxDuration = maxDuration
        self.onRecorded = onRecorded
        self.errorMessage = nil
        self.infoMessage = nil

#if targetEnvironment(simulator)
        useSimulatorFallback = true
#else
        Task {
            let cameraGranted = await requestVideoAccessIfNeeded()

            guard cameraGranted else {
                DispatchQueue.main.async {
                    self.errorMessage = "Camera permission is required to record clips."
                }
                return
            }

            let microphoneGranted = await requestAudioAccessIfNeeded()
            if !microphoneGranted {
                DispatchQueue.main.async {
                    self.errorMessage = "Microphone permission is off. Videos will record without audio."
                }
            }

            configureSessionIfNeeded(includeAudio: microphoneGranted)
            startSession()
        }
#endif
    }

    func updateEffectConfig(_ config: CoppedVideoEffectConfig) {
        effectConfig = config
    }

    func startRecording() {
        guard isConfigured else { return }
        guard !isFinalizing else { return }
        guard !movieOutput.isRecording else { return }
        guard isSessionRunning else {
            errorMessage = "Camera is still preparing. Try again."
            return
        }

        errorMessage = nil
        isFinalizing = false
        elapsed = 0

        let outputURL = Self.tempMovieURL()
        movieOutput.maxRecordedDuration = CMTime(seconds: maxDuration, preferredTimescale: 600)
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        isFinalizing = true
        movieOutput.stopRecording()
    }

    func stopSession() {
        timer?.invalidate()
        timer = nil

#if !targetEnvironment(simulator)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isSessionRunning = false
                self.previewImage = nil
            }
        }
#endif
    }

    // MARK: - Permissions

    private func requestVideoAccessIfNeeded() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await requestAccess(for: .video)
        @unknown default:
            return false
        }
    }

    private func requestAudioAccessIfNeeded() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await requestAccess(for: .audio)
        @unknown default:
            return false
        }
    }

    private func requestAccess(for mediaType: AVMediaType) async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: mediaType) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Session

    private func configureSessionIfNeeded(includeAudio: Bool) {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .high
        session.automaticallyConfiguresApplicationAudioSession = true

        defer {
            session.commitConfiguration()
            isConfigured = true
        }

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput)
        else {
            errorMessage = "Unable to configure camera input."
            return
        }

        session.addInput(videoInput)

        if includeAudio {
            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
               session.canAddInput(audioInput) {
                session.addInput(audioInput)
            } else if errorMessage == nil {
                errorMessage = "Microphone is unavailable. Videos may record without audio."
            }
        }

        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        } else {
            errorMessage = "Unable to configure video output."
            return
        }

        configureLiveFXOutputIfPossible()
    }

    private func configureLiveFXOutputIfPossible() {
        guard CoppedLiveFXRuntime.previewEnabled else {
            useLiveFXPreview = false
            return
        }

        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        videoDataOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        guard session.canAddOutput(videoDataOutput) else {
            useLiveFXPreview = false
            infoMessage = "Live effects preview unavailable on this device."
            return
        }

        session.addOutput(videoDataOutput)

        if let connection = videoDataOutput.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }

        useLiveFXPreview = true
        didFallbackLiveFX = false
        infoMessage = "Rio look previews are live. Final video is normalized to 720p/30fps."
    }

    private func fallbackToStandardPreviewIfNeeded() {
        guard !didFallbackLiveFX else { return }
        didFallbackLiveFX = true

        DispatchQueue.main.async {
            self.useLiveFXPreview = false
            self.previewImage = nil
            self.infoMessage = "Live effects preview failed. Recording continues with standard preview."
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.session.isRunning else {
                DispatchQueue.main.async {
                    self.isSessionRunning = true
                }
                return
            }
            self.session.startRunning()
            DispatchQueue.main.async {
                let didStart = self.session.isRunning
                self.isSessionRunning = didStart
                if !didStart, self.errorMessage == nil {
                    self.errorMessage = "Camera did not start. Check permissions and try again."
                }
            }
        }
    }

    private func beginTimer() {
        timer?.invalidate()
        recordingStartDate = Date()

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard let start = self.recordingStartDate else { return }

            self.elapsed = Date().timeIntervalSince(start)
            if self.elapsed >= self.maxDuration {
                self.stopRecording()
            }
        }
    }

    private func finishRecording(outputURL: URL, error: Error?) {
        timer?.invalidate()
        timer = nil
        isRecording = false
        isFinalizing = false

        let asset = AVURLAsset(url: outputURL)
        let loadedDuration = CMTimeGetSeconds(asset.duration)
        let measuredDuration = elapsed
        let duration = if loadedDuration.isFinite, loadedDuration > 0 {
            loadedDuration
        } else {
            measuredDuration
        }
        let hasFile = FileManager.default.fileExists(atPath: outputURL.path)
        let hasUsableVideo = hasFile && duration.isFinite && duration > 0

        if let error, !hasUsableVideo {
            errorMessage = "Recording failed. \(error.localizedDescription)"
            return
        }

        guard duration.isFinite, duration >= minDuration else {
            errorMessage = "Clip must be at least \(Int(minDuration)) seconds."
            try? FileManager.default.removeItem(at: outputURL)
            return
        }

        let boundedDuration = max(minDuration, min(duration, maxDuration))

        onRecorded?(
            CoppedRecordedVideo(
                fileURL: outputURL,
                durationSeconds: Int(boundedDuration.rounded()),
                captureMode: .camera
            )
        )
    }

    private static func previewImage(from sampleBuffer: CMSampleBuffer, look: CoppedVideoLook, ciContext: CIContext) -> UIImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        var image = CIImage(cvPixelBuffer: imageBuffer)
        image = applyLook(look, to: image)
        image = image.oriented(forExifOrientation: 6)

        let targetWidth: CGFloat = 520
        let width = max(image.extent.width, 1)
        let scale = targetWidth / width
        let resized = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = ciContext.createCGImage(resized, from: resized.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private static func applyLook(_ look: CoppedVideoLook, to input: CIImage) -> CIImage {
        switch look {
        case .none:
            return input

        case .rioHeat:
            var image = input
            image = applyColorControls(to: image, saturation: 1.22, contrast: 1.12, brightness: 0.04)
            image = applyTemperature(to: image, neutral: CIVector(x: 6500, y: 0), target: CIVector(x: 8200, y: 20))
            return image

        case .goldenHour:
            var image = input
            image = applyColorControls(to: image, saturation: 1.15, contrast: 1.05, brightness: 0.05)
            image = applySepia(to: image, intensity: 0.17)
            return image

        case .coolTeal:
            var image = input
            image = applyColorControls(to: image, saturation: 1.12, contrast: 1.1, brightness: -0.01)
            image = applyTemperature(to: image, neutral: CIVector(x: 6500, y: 0), target: CIVector(x: 5000, y: -10))
            return image
        }
    }

    private static func applyColorControls(
        to image: CIImage,
        saturation: CGFloat,
        contrast: CGFloat,
        brightness: CGFloat
    ) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(saturation, forKey: kCIInputSaturationKey)
        filter.setValue(contrast, forKey: kCIInputContrastKey)
        filter.setValue(brightness, forKey: kCIInputBrightnessKey)
        return filter.outputImage ?? image
    }

    private static func applyTemperature(
        to image: CIImage,
        neutral: CIVector,
        target: CIVector
    ) -> CIImage {
        guard let filter = CIFilter(name: "CITemperatureAndTint") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(neutral, forKey: "inputNeutral")
        filter.setValue(target, forKey: "inputTargetNeutral")
        return filter.outputImage ?? image
    }

    private static func applySepia(to image: CIImage, intensity: CGFloat) -> CIImage {
        guard let filter = CIFilter(name: "CISepiaTone") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
        return filter.outputImage ?? image
    }

    private static func tempMovieURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("copped-\(UUID().uuidString).mov")
    }
}

extension CoppedCameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        DispatchQueue.main.async {
            self.isRecording = true
            self.isFinalizing = false
            self.elapsed = 0
            self.beginTimer()
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.finishRecording(outputURL: outputFileURL, error: error)
        }
    }
}

extension CoppedCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard useLiveFXPreview else { return }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        if timestamp.isFinite {
            if timestamp - lastPreviewTimestamp < (1.0 / 12.0) {
                return
            }
            lastPreviewTimestamp = timestamp
        }

        let look = effectConfig.look
        guard let frame = Self.previewImage(from: sampleBuffer, look: look, ciContext: ciContext) else {
            fallbackToStandardPreviewIfNeeded()
            return
        }

        DispatchQueue.main.async {
            if self.useLiveFXPreview {
                self.previewImage = frame
            }
        }
    }
}

struct CoppedCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
