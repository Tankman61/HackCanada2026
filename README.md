# Reactiv ClipKit Lab

An App Clip simulator for Hack Canada. Build creative App Clip experiences without needing entitlements, Associated Domains, or an Apple Developer account.

An App Clip is a lightweight slice of an app that lets users complete a specific task quickly without downloading the full app. They can be triggered by:

- Scanning an App Clip code (similar to a QR code)
- Tapping an NFC tag
- Tapping a link sent via iMessage
- Tapping a Smart App Banner in Safari
- Siri suggestions or Apple Maps

No install, no login, no onboarding. Apple designed them for "30-second moments." Most people only think of them as "scan to pay." **Your challenge: what else should App Clips be used for that nobody has built yet?**

## About Reactiv

Reactiv is a platform for building and managing mobile commerce apps for e-commerce businesses. Its key differentiator is **Reactiv Clips**, powered by Apple's App Clip technology.

### Reactiv Clips

Reactiv Clips bring App Clip technology to any Shopify merchant. Install directly from the Shopify App Store, build Clip experiences with a drag-and-drop visual builder or generate them with AI, and go live without writing code. Clips support configurable push notifications, giving brands up to 8 hours of direct, time-sensitive engagement after a single interaction. No app install, no account creation. Just instant access and a direct communication channel.

Reactiv integrates natively with Shopify for product catalog, cart, and checkout, and supports third-party providers for payments and analytics.

Learn more: [Reactiv Mobile App Builder](https://reactiv.ai/)

## Problem Statements

Here are example problem statements from Reactiv. Pick one, combine elements from several, or invent your own and build a Clip that solves it. These are meant to spark ideas, not limit them. If you see a problem worth solving that isn't listed here, go for it.

When you're done, create a branch and open a pull request with a description that explains your solution. Include screen recordings of it working so judges can see the experience in action.

Starter templates are provided so you can focus on your solution, not scaffolding. Reactiv retains ownership of submitted code.

---

### AI-Powered Personalization

**Scenario:** A customer walks up to a coffee shop counter, scans a QR code, and a Clip launches. Using available context like time of day, weather, and location, the Clip delivers intelligent, personalized recommendations without any login or stored preferences.

**The problem:** Personalization today requires accounts, history, and data collection. App Clips have none of that. But context is everywhere: time, location, weather, device locale, even the URL itself. AI can bridge the gap between zero knowledge and a tailored experience.

**Key questions to explore:**

- How do you personalize meaningfully with no user history or stored preferences?
- What contextual signals (time, location, weather, URL parameters) can drive smart defaults?
- How do you make AI-driven recommendations feel helpful rather than invasive in a zero-trust environment?

---

### In-Store Companion Shopping

**Scenario:** A shopper walks into a retail location. The store's App Clip surfaces automatically via Apple Maps, geo-fenced Siri Suggestions, or an in-store QR code. The Clip becomes a companion shopping experience: browse products, view details and pricing, and self-checkout directly from the phone.

**The problem:** In-store shopping still relies on checkout lines, clunky kiosks, and staff availability. A Clip could replace all of that, but only if product discovery is fast and payment is seamless in an ephemeral, no-account experience.

**Key questions to explore:**

- How do you make product discovery fast and intuitive in a Clip?
- How does self-checkout work in an ephemeral, no-account experience?
- What does the transition from browsing to payment look like in under 30 seconds?

**Tip:** The Shopify Storefront API and Shopify CheckoutSheet Kit make it easy to handle product browsing and checkout. Stripe is another option for payment processing.

---

### Ad-to-Clip Commerce

**Scenario:** A shopper sees an ad on Instagram, taps it, and lands in an App Clip instead of a mobile website. A faster, more polished native experience. They browse products, add items to their cart, and leave. The Clip fires push notifications at intervals (15 minutes, 1 hour, 8 hours) to bring them back to complete checkout. After purchasing, the shopper is prompted to download the full app.

**The problem:** Mobile ad funnels are broken. Click-through rates are low, mobile web is slow, and users abandon carts constantly. A Clip offers a native-quality experience at web-link speed, but the challenge is keeping users engaged across sessions without a full app install.

**Key questions to explore:**

- How do you make the ad-to-Clip transition feel instant and seamless?
- How do you design a cart and checkout flow that survives the user leaving and returning?
- How do you use push notifications effectively without being intrusive?
- What does the handoff from Clip to full app look like?

**Tip:** The Shopify Storefront API and Shopify CheckoutSheet Kit make it easy to handle cart and checkout flows. Stripe is another option for payment processing.

---

### Live Events — Arenas, Concerts & Sports

**Scenario:** A fan arrives at a venue, scans a QR code, and a Clip launches instantly, enabling merch purchases, real-time engagement, signups, and more.

**The problem:** Artists and performers don't know who their audience is. Ticket platforms report sales totals but share zero fan-level data. Artists end up running ads just to reconnect with people who already showed up.

**Key questions to explore:**

- How can a Clip capture fan identity at scale with no app install and no friction?
- How can it power real-time engagement during an event?
- How can it enable merch sales and audience building in a single interaction?

Consider the full lifecycle of a concert-goer when deciding where your solution should intervene. Your solution should target **at least one** of these touchpoints and make a clear case for why it represents the most valuable opportunity.

1. **Discovery** — A fan learns about a concert in their city through social media ads, posts from friends, or organic search.
2. **Ticket Purchase** — The fan browses and buys tickets through Ticketmaster or a similar platform.
3. **The Wait** — The period between buying tickets and the show itself — often weeks or months. Fans are engaged but have no direct relationship with One Live.
4. **Show Day** — The fan arrives at the venue, waits in queues, and moves through the event experience. High purchase intent, high friction.
5. **Post-Show Afterglow** — The fan leaves the show in a heightened emotional state. Engagement and nostalgia are high in the hours and days that follow.

## Assumptions & Constraints

- **iOS only.** Your solution needs to work on iPhone. Reactiv Clips are an Apple technology (App Clips). Over 80% of North American mobile commerce occurs on iPhones, so an iOS-only solution is commercially reasonable.
- Avoid trivial builds (e.g., coupon/discount apps with no depth).
- Think commercially and technically. Aim for solutions that could ship or directly inform product roadmap decisions.
- Reasonable assumptions are allowed where integrations are unavailable (e.g., Shopify API access may be provided).
- All implementations should be runnable Swift-based Clips built on this starter kit.

## Setup

1. Download [Xcode 26+](https://developer.apple.com/xcode/) from the Mac App Store or Apple Developer website (free, requires a Mac)
2. Clone this repository
3. Open `ReactivChallengeKit.xcodeproj` in Xcode
4. Select an iPhone simulator
5. Build and Run (Cmd+R)

No dependencies. No SPM packages. If Xcode works, the project works.

## How to Build Your Clip

### Step 1: Create Your File

Duplicate `Examples/EmptyClipExperience.swift` and rename it.

### Step 2: Conform to the Protocol

```swift
struct MyClipExperience: ClipExperience {
    static let urlPattern = "myapp.com/action/:id"
    static let clipName = "My Clip"
    static let clipDescription = "One line about what it does."

    let context: ClipContext

    var body: some View {
        // Your SwiftUI UI here
        // Access context.pathParameters["id"] for the URL parameter
        // Access context.queryParameters for ?key=value pairs
    }
}
```

### Step 3: Register Your Clip

Open `Simulator/ClipRouter.swift` and add your type to `allExperiences`:

```swift
static let allExperiences: [any ClipExperience.Type] = [
    HelloClipExperience.self,
    MyClipExperience.self,  // <-- add this
]
```

### Step 4: Test It

Run the app, type your invocation URL in the console (e.g., `myapp.com/action/42`), and tap the send button. Or tap a registered clip card on the landing page.

## What You Get

| Component             | What It Does                                                                     |
| --------------------- | -------------------------------------------------------------------------------- |
| **InvocationConsole** | URL input with send button. Simulates how real clips are triggered by URLs.      |
| **ClipRouter**        | Matches URLs against registered patterns and extracts path parameters.           |
| **ConstraintBanner**  | "App Clip Preview — Get the full app" bar. Always visible, just like real clips. |
| **MomentTimer**       | Seconds-since-invocation pill. Green < 20s, yellow < 30s, red >= 30s.            |

## What You Bring

Everything else is yours. Use any iOS framework: URLSession, CoreLocation, MapKit, AVFoundation, CoreNFC, or any SwiftUI view.

No mock services are provided. You choose the domain, the data, and the experience.

## What You Should Deliver

Your submission should address the following:

- **Problem framing** — Which touchpoint(s) in the customer journey are you targeting, and why? What friction or missed opportunity are you solving for?
- **Proposed solution** — How does your solution use Reactiv Clips? How is the Clip invoked? What does the user experience look like end-to-end?
- **Platform extensions (if applicable)** — If your solution requires new Reactiv Clips capabilities, describe what they are and how they would work.
- **Prototype or mockup** — A visual demonstration of the key user flows (wireframes, clickable prototype, or equivalent).
- **Impact hypothesis** — How does your solution increase One Live's merchandise revenue? Be specific about which channel (venue, online, or both) and why.

## Project Structure

```
ReactivChallengeKit/
  App/
    ReactivChallengeKitApp.swift   # App entry point
  Simulator/
    SimulatorShell.swift           # Main container + clip host
    ClipRouter.swift               # URL pattern matching
    LandingView.swift              # Home screen with clip cards
    InvocationConsole.swift        # URL input
    ConstraintBanner.swift         # Download banner
    MomentTimer.swift              # Elapsed time overlay
  Protocol/
    ClipExperience.swift           # Protocol you conform to
    ClipContext.swift              # URL data passed to your clip
  Examples/
    HelloClipExperience.swift      # Working example (protocol demo)
    TrailCheckInExperience.swift   # Working example (non-trivial clip)
    EmptyClipExperience.swift      # Your starting template
```

## Challenge Rules

1. Your clip must be invoked via URL (use the InvocationConsole)
2. Your experience should deliver value in under 30 seconds (watch the timer)
3. Your clip should make sense as a no-install, ephemeral experience
4. Fill out `SUBMISSION.md` with your team info and idea description
5. Read `CONSTRAINTS.md` to understand real App Clip constraints

## Judging Criteria

| Criteria                   | Weight |
| -------------------------- | ------ |
| Novelty of use case        | 30%    |
| Constraint awareness       | 25%    |
| Real-world trigger quality | 20%    |
| Execution / demo           | 15%    |
| Scalability of the idea    | 10%    |

The question is NOT "can you build an iOS app?" The question is: **"what experience fits the shape of an App Clip that nobody has thought of?"**

## Supporting Resources

- [Apple App Clips Developer Documentation](https://developer.apple.com/documentation/appclip)
