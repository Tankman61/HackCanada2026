//  VenueMerchExperience.swift
//  ReactivChallengeKit
//
//  Copyright © 2025 Reactiv Technologies Inc. All rights reserved.
//

import SwiftUI

struct VenueMerchExperience: ClipExperience {
    static let urlPattern = "example.com/venue/:venueId/merch"
    static let clipName = "Venue Merch"
    static let clipDescription = "Open from a venue trigger to browse and buy merch fast."
    static let touchpoint: JourneyTouchpoint = .showDay
    static let invocationSource: InvocationSource = .qrCode

    let context: ClipContext
    @State private var cart: [Product] = []
    @State private var purchased = false

    private var artist: Artist {
        ChallengeMockData.artists[0]
    }

    private var venueName: String {
        let venueId = context.pathParameters["venueId"] ?? ""
        return ChallengeMockData.venues.first { $0.name.lowercased().contains(venueId.lowercased()) }?.name
            ?? ChallengeMockData.venues[0].name
    }

    var body: some View {
        ZStack {
            if purchased {
                VStack(spacing: 20) {
                    Spacer()
                    ClipSuccessOverlay(
                        message: "Order confirmed!\nPick up at \(ChallengeMockData.venues[0].boothLocations[0])."
                    )
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ArtistBanner(artist: artist, venue: venueName)
                            .padding(.top, 8)

                        MerchGrid(products: ChallengeMockData.featuredProducts) { product in
                            cart.append(product)
                        }

                        if !cart.isEmpty {
                            CartSummary(items: cart) {
                                withAnimation(.spring(duration: 0.4)) {
                                    purchased = true
                                }
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                .animation(.spring(duration: 0.3), value: cart.count)
            }
        }
    }
}
