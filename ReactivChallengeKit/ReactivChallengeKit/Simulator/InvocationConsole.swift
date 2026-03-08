//  InvocationConsole.swift
//  ReactivChallengeKit
//
//  Copyright © 2025 Reactiv Technologies Inc. All rights reserved.
//

import SwiftUI

/// URL text field + invoke button. Replaces Associated Domains for simulation.
struct InvocationConsole: View {
    @Bindable var router: ClipRouter
    @State private var urlText = ""
    @State private var nfcStatusMessage: String?
    @State private var showNFCSimulatorSheet = false
    @State private var nfcPayloadText = "clip.copped.app/v/hoodie"
    @FocusState private var isTextFieldFocused: Bool
    
    private let creatorPresets: [(label: String, payload: String)] = [
        ("Demo Hoodie", "clip.copped.app/c/demo?product=hoodie"),
        ("Demo Book", "clip.copped.app/c/demo?product=book"),
        ("Demo Food", "clip.copped.app/c/demo?product=food"),
    ]

    private let viewerPresets: [(label: String, payload: String)] = [
        ("View Hoodie", "clip.copped.app/v/hoodie"),
        ("View Book", "clip.copped.app/v/book"),
        ("View Food", "clip.copped.app/v/food"),
    ]

    var body: some View {
        VStack(spacing: 8) {
            if let error = router.errorMessage {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let nfcStatusMessage {
                Text(nfcStatusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.blue)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            GlassEffectContainer {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.tertiary)

                    TextField("Enter invocation URL...", text: $urlText)
                        .font(.system(size: 15))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($isTextFieldFocused)
                        .onSubmit { invokeURL() }

                    if !urlText.isEmpty {
                        Button {
                            urlText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Button(action: openNFCSimulatorSheet) {
                        Image(systemName: "wave.3.right.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.blue)
                    }

                    Button(action: invokeURL) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(urlText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                    }
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.horizontal, 16)

            if !router.invocationHistory.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer {
                        HStack(spacing: 6) {
                            ForEach(Array(router.invocationHistory.prefix(5).enumerated()), id: \.offset) { item in
                                let url = item.element
                                Button {
                                    urlText = url.absoluteString
                                        .replacingOccurrences(of: "https://", with: "")
                                    invokeURL()
                                } label: {
                                    Text(url.host ?? url.absoluteString)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .glassEffect(.regular.interactive(), in: .capsule)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .scrollClipDisabled()
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 4)
            }
        }
        .animation(.easeOut(duration: 0.2), value: router.errorMessage)
        .sheet(isPresented: $showNFCSimulatorSheet) {
            nfcSimulatorSheet
        }
    }

    private var nfcSimulatorSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Simulate NFC Tag Payload")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Text("No paid Apple Developer account needed. Paste tag content as either a product ID (`hoodie`) or full URL.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                TextField("clip.copped.app/v/hoodie", text: $nfcPayloadText)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Presets")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(creatorPresets, id: \.label) { preset in
                            quickPayloadButton(label: preset.label, payload: preset.payload)
                        }
                    }

                    HStack(spacing: 8) {
                        ForEach(viewerPresets, id: \.label) { preset in
                            quickPayloadButton(label: preset.label, payload: preset.payload)
                        }
                    }
                }

                Text(nfcPayloadText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 2)

                Spacer(minLength: 0)

                Button("Invoke From Simulated NFC") {
                    invokeFromSimulatedNFC(payload: nfcPayloadText)
                }
                .buttonStyle(.borderedProminent)
                .disabled(nfcPayloadText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(18)
        }
        .presentationDetents([.medium])
    }

    private func quickPayloadButton(label: String, payload: String) -> some View {
        Button {
            nfcPayloadText = payload
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
    }

    private func invokeURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        nfcStatusMessage = nil
        isTextFieldFocused = false
        router.invoke(urlString: trimmed)
    }

    private func openNFCSimulatorSheet() {
        isTextFieldFocused = false
        showNFCSimulatorSheet = true
    }

    private func invokeFromSimulatedNFC(payload: String) {
        guard let normalized = NFCInvocationScanner.normalizeInvocationURL(from: payload) else {
            nfcStatusMessage = "Could not parse NFC payload. Use a product ID like hoodie or full viewer/creator URL."
            return
        }

        showNFCSimulatorSheet = false
        urlText = normalized.replacingOccurrences(of: "https://", with: "")
        nfcStatusMessage = "Simulated NFC opened \(urlText)."
        router.invoke(urlString: normalized)
    }
}
