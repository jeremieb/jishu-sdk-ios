# Jishu iOS SDK

![github package](https://github.com/user-attachments/assets/161cb128-4312-4dd2-b69c-a47698ee8096)

A lightweight Swift package for [Jishu](https://jishu.page) — check promo access grants, send contact form messages, and collect feature proposals from iOS apps.

- **Current version:** `0.1.4`
- **Minimum platform:** iOS 15
- **Swift:** 6.0+

---

## Table of Contents

1. [What is Jishu promo access?](#what-is-jishu-promo-access)
2. [Installation](#installation)
3. [Quickstart](#quickstart)
4. [Contact form](#contact-form)
5. [Feature feedback](#feature-feedback)
6. [User identity and `displayUserID`](#user-identity-and-displayuserid)
7. [Debug logging](#debug-logging)
8. [Staging smoke test](#staging-smoke-test)
9. [RevenueCat integration](#revenuecat-integration)
10. [Reinstall limitation](#reinstall-limitation)
11. [Security notes](#security-notes)
12. [Publishing a new version](#publishing-a-new-version)
13. [Running the tests](#running-the-tests)

---

## What is Jishu promo access?

Jishu promo access lets you grant specific users or devices early or exclusive access to your app — without going through the App Store review cycle. You create grants in the Jishu dashboard (by user ID, device ID, or phone ID) and this SDK checks at runtime whether the current user holds an active grant.

---

## Installation

### Swift Package Manager (Xcode)

1. In Xcode open **File → Add Package Dependencies…**
2. Paste the repository URL:
   ```
   https://github.com/jeremieberduck/jishu-sdk-ios
   ```
3. Select **Up to Next Major Version** starting from `0.1.4`.
4. Add **Jishu** to your app target.

### Swift Package Manager (Package.swift)

```swift
dependencies: [
    .package(url: "https://github.com/jeremieberduck/jishu-sdk-ios", from: "0.1.4"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: ["Jishu"]
    ),
]
```

---

## Quickstart

### 1. Configure once at startup

Call `configure` from `AppDelegate` or the entry point of your SwiftUI app, before any other SDK call.

```swift
import Jishu

// AppDelegate
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    Jishu.configure(
        baseURL: URL(string: "https://jishu.page")!,
        apiToken: "YOUR_API_TOKEN",
        appId: "YOUR_APP_ID"
    )
    return true
}

// SwiftUI @main
@main
struct MyApp: App {
    init() {
        Jishu.configure(
            baseURL: URL(string: "https://jishu.page")!,
            apiToken: "YOUR_API_TOKEN",
            appId: "YOUR_APP_ID"
        )
    }
    var body: some Scene { WindowGroup { ContentView() } }
}
```

### 2. Check access

```swift
do {
    let result = try await Jishu.checkAccess()
    if result.granted {
        // Show exclusive content
    }
} catch {
    // Handle JishuError (e.g. notConfigured, httpError, decodingFailed)
}
```

Pass your own user ID when the customer is signed in — this is the preferred mode:

```swift
let result = try await Jishu.checkAccess(externalUserId: currentUser.id)
```

### 3. Add feedback in your app

Once the SDK is configured, you can call the public feedback endpoints from any `ObservableObject`, `ViewModel`, or other async context. The SDK automatically uses the configured `appId` and a stable device-scoped voter token.

If you want to expose feature requests in your UI, see the [Feature feedback](#feature-feedback) section below for a complete example.

---

## Contact form

`Jishu.sendContactMessage(_:)` lets your users send a message directly to you from within your app. Messages land in the **User Messages** inbox in your Jishu dashboard, where you can read and reply via email.

### Basic usage

```swift
do {
    try await Jishu.sendContactMessage(ContactMessage(
        senderEmail: "jane@example.com",
        body: "Hi, I have a question about my account."
    ))
    // Show a "Message sent!" confirmation
} catch JishuError.httpError(429) {
    // Rate limit hit — ask the user to wait before trying again
} catch {
    // Network error or validation failure
}
```

### `ContactMessage` fields

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `senderEmail` | `String` | Yes | Must be a valid email address |
| `body` | `String` | Yes | Max 5 000 characters |
| `senderName` | `String?` | No | Displayed in the dashboard message list |
| `subject` | `String?` | No | Shown as the message subject line |
| `userId` | `String?` | No | Automatically filled with `Jishu.displayUserID` when `nil`. Lets the app owner add this sender to a promo grant directly from the dashboard. |

The SDK automatically includes `platform: "ios"`, `osName`, `osVersion`, and `deviceName` in every contact message request. `deviceName` carries the raw Apple hardware identifier such as `iPhone17,1`; the Jishu backend resolves that into a friendly marketing name for the dashboard.

```swift
// All fields
let message = ContactMessage(
    senderName: "Jane Smith",
    senderEmail: "jane@example.com",
    subject: "Question about my portfolio",
    body: "I noticed that my site is not loading correctly on Safari..."
    // userId is automatically filled with Jishu.displayUserID
)
try await Jishu.sendContactMessage(message)
```

### Rate limiting

The endpoint is public (no API token required) and rate-limited to **10 messages per hour per IP address** per app. On limit hit, `JishuError.httpError(429)` is thrown. Show a user-friendly message and do not retry automatically.

### Errors

| Error | Meaning |
|-------|---------|
| `JishuError.notConfigured` | `Jishu.configure(...)` was not called before sending |
| `JishuError.httpError(400)` | Validation failed (missing email or body, value too long) |
| `JishuError.httpError(404)` | The `appId` supplied to `configure` does not exist or is inactive |
| `JishuError.httpError(429)` | Rate limit — more than 10 messages/hour from this IP |
| `JishuError.httpError(500)` | Server error — the SDK retries once automatically |

### SwiftUI example

```swift
struct ContactFormView: View {
    @State private var email = ""
    @State private var body  = ""
    @State private var state: FormState = .idle

    enum FormState { case idle, sending, success, error(String) }

    var body: some View {
        Form {
            TextField("Your email", text: $email)
                .keyboardType(.emailAddress)
            TextEditor(text: $body)
                .frame(minHeight: 120)
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Send") { send() }
                    .disabled(email.isEmpty || body.isEmpty || state == .sending)
            }
        }
        .overlay {
            if case .success = state {
                Text("Message sent!").foregroundStyle(.green)
            }
        }
    }

    private func send() {
        state = .sending
        Task {
            do {
                try await Jishu.sendContactMessage(
                    ContactMessage(senderEmail: email, body: body)
                )
                state = .success
            } catch JishuError.httpError(429) {
                state = .error("Too many messages — please wait an hour and try again.")
            } catch {
                state = .error("Could not send message. Please try again.")
            }
        }
    }
}
```

---

## Feature feedback

`Jishu.fetchProposals()`, `Jishu.submitProposal(...)`, and `Jishu.vote(on:)` wrap the public feedback endpoints for the configured app. No auth header is sent on these requests.

### What you need before using it

1. Call `Jishu.configure(...)` once at app startup.
2. Use the same `appId` that is registered in your Jishu dashboard.
3. Make sure the backend feedback routes are live for that app:
   `GET /api/apps/:appId/proposals`
   `POST /api/apps/:appId/proposals`
   `POST /api/apps/:appId/proposals/:id/vote`

### Basic usage

```swift
let proposals = try await Jishu.fetchProposals()

let created = try await Jishu.submitProposal(
    title: "Offline mode",
    description: "Let me keep reading when I lose connection."
)

let updatedVoteCount = try await Jishu.vote(on: created)
```

The feedback endpoints send these metadata fields automatically:

- `osName` — for example `iOS`
- `osVersion` — for example `18.3.2`
- `deviceName` — raw Apple hardware identifier such as `iPhone17,1`

The Jishu backend resolves `deviceName` into a friendly marketing name for dashboard display, so the SDK does not bundle a local device-name lookup table.

### Typical app integration

The simplest integration is:

1. Load proposals when the screen opens with `Jishu.fetchProposals()`.
2. Submit a new idea with `Jishu.submitProposal(title:description:)`.
3. Update the vote count for an item with `Jishu.vote(on:)`.
4. Store the result in your own screen state; the SDK does not manage UI state for you.

### SwiftUI example

```swift
import Jishu
import SwiftUI

@MainActor
final class FeedbackViewModel: ObservableObject {
    @Published var proposals: [JishuProposal] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            proposals = try await Jishu.fetchProposals()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submit(title: String, description: String?) async {
        do {
            let proposal = try await Jishu.submitProposal(title: title, description: description)
            proposals.insert(proposal, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func vote(on proposal: JishuProposal) async {
        do {
            let updatedCount = try await Jishu.vote(on: proposal)
            if let index = proposals.firstIndex(where: { $0.id == proposal.id }) {
                proposals[index] = JishuProposal(
                    id: proposal.id,
                    title: proposal.title,
                    description: proposal.description,
                    status: proposal.status,
                    voteCount: updatedCount,
                    createdAt: proposal.createdAt
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

### Public API

```swift
public static func fetchProposals() async throws -> [JishuProposal]
public static func submitProposal(title: String, description: String?) async throws -> JishuProposal
public static func vote(on proposal: JishuProposal) async throws -> Int
```

### Models

| Type | Notes |
|------|-------|
| `JishuProposal` | `id`, `title`, `description`, `status`, `voteCount`, `createdAt` |
| `JishuProposalStatus` | `open`, `planned`, `inProgress`, `shipped`, `rejected` |

### Behavior notes

- `submitProposal` and `vote(on:)` use a stable device-scoped voter token managed by the SDK.
- Proposal submissions and votes include `osName`, `osVersion`, and the raw Apple hardware identifier in `deviceName`.
- The feedback endpoints are public and rate-limited by the backend.
- Duplicate votes from the same device are ignored by the server.
- The SDK retries once on transport failures or 5xx responses, matching the contact form behavior.

### Common errors

| Error | Meaning |
|-------|---------|
| `JishuError.notConfigured` | `Jishu.configure(...)` was not called before use |
| `JishuError.httpError(400)` | Validation failed |
| `JishuError.httpError(404)` | The configured `appId` does not exist or is inactive |
| `JishuError.httpError(429)` | Rate limit — too many proposals or votes from the same IP/device window |
| `JishuError.httpError(500)` | Server error after one retry |

## User identity and `displayUserID`

`Jishu.displayUserID` is a stable, device-scoped identifier automatically generated on first launch and persisted in `UserDefaults`. You can use it as a device identity in the Jishu dashboard.

```swift
print(Jishu.displayUserID) // e.g. "550E8400-E29B-41D4-A716-446655440000"
```

**When to use `displayUserID` vs `externalUserId`:**

| Scenario | Recommended approach |
|---|---|
| App has its own auth system | Pass `externalUserId: currentUser.id` — most reliable |
| Unauthenticated app or guest mode | Omit `externalUserId`; the SDK sends `displayUserID` automatically |

Grants are matched on the server side against whichever identity you send. Mixing both identities in different calls for the same user can produce inconsistent results.

**`displayUserID` and contact messages:**

When a user submits a contact form, the SDK automatically includes their `displayUserID` as the `userId` field of the message. This lets you see the sender's Jishu identity directly in the **User Messages** dashboard and add them to a promo grant with one click — no copy-pasting required. If your app has its own auth system, pass an explicit `userId` to `ContactMessage` to use your stable user ID instead:

```swift
try await Jishu.sendContactMessage(ContactMessage(
    senderEmail: "jane@example.com",
    body: "Hi, I have a question.",
    userId: currentUser.id   // override with your own stable ID
))
```

---

## Debug logging

Pass `debugLevel` to `configure()` to control what the SDK prints to the console. When omitted, the default level is used.

| Level | Behavior |
|-------|----------|
| `.default` | Prints errors only (HTTP failures, transport errors, failed retries). Each line is prefixed with `‼️ Jishu -`. |
| `.verbose` | Prints all SDK activity — outgoing requests, HTTP status codes, retries, and errors. Each line is prefixed with `📱 Jishu -`. |

```swift
// Errors only (default — same as omitting the parameter)
Jishu.configure(
    baseURL: URL(string: "https://jishu.page")!,
    apiToken: "YOUR_API_TOKEN",
    appId: "YOUR_APP_ID",
    debugLevel: .default
)

// Full request/response trace
Jishu.configure(
    baseURL: URL(string: "https://jishu.page")!,
    apiToken: "YOUR_API_TOKEN",
    appId: "YOUR_APP_ID",
    debugLevel: .verbose
)
```

Example `.verbose` output:

```
📱 Jishu - Sending POST https://jishu.page/api/v1/mobile/entitlements/check
📱 Jishu - HTTP 200
```

Example `.default` output (error scenario):

```
‼️ Jishu - Server error 503, retrying...
‼️ Jishu - Server error 503 — no retries left
```

> **Tip:** Use `.verbose` during development and staging smoke tests. Switch to `.default` (or omit the parameter) in production to keep your logs quiet unless something goes wrong.

---

## Staging smoke test

Use this flow to verify the SDK works end-to-end against the live staging environment before shipping to production.

### Prerequisites

1. Create an app in the Jishu staging dashboard at `https://staging.jishu.page`.
2. Create a promo grant for a **User ID** or **Phone ID** in the app's Promo Access section.
3. Create an API token under **Account → API Access**.

### Configure for staging

```swift
Jishu.configure(
    baseURL: URL(string: "https://staging.jishu.page")!,
    apiToken: "YOUR_STAGING_API_TOKEN",
    appId: "YOUR_STAGING_APP_ID",
    environment: "staging",
    debugLevel: .verbose          // prints request/response info to console
)
```

### Call `checkAccess`

```swift
let result = try await Jishu.checkAccess(externalUserId: "the_user_id_you_granted")
print(result.granted)    // true
print(result.matchType)  // .user
print(result.expiresAt)  // optional Date
```

Expected successful response shape:

```
granted    = true
matchType  = .user  (or .device)
expiresAt  ≠ nil
```

---

## RevenueCat integration

RevenueCat support is **not included in this first release** to keep the core package dependency-free.

A RevenueCat bridge will be added in a future minor release as an opt-in source file (or separate target), so the core package remains usable without RevenueCat installed.

**Planned API shape (subject to change):**

```swift
let result = try await Jishu.hasAccessWithRevenueCat(
    entitlementID: "pro",
    externalUserId: currentUser.id
)
// result.jishuGranted || result.revenueCatEntitled
```

**Notes when RevenueCat support lands:**

- Authenticated apps should use the same stable user ID for both `Purchases.shared.logIn(appUserID:)` and `Jishu.checkAccess(externalUserId:)`.
- Unauthenticated apps may use `Jishu.displayUserID`, but see the [reinstall warning](#reinstall-limitation) below.

---

## Reinstall limitation

> **Warning:** Reinstalling the app generates a new `displayUserID`.

Any active promo grant that was matched via the old device ID will no longer match after reinstall. This is a limitation of device-scoped identity stored in `UserDefaults` (which is cleared on uninstall on iOS).

**Mitigations:**

- Use `externalUserId` whenever the user is authenticated — server-side user IDs survive reinstalls.
- Document to your users that reinstalling requires re-enrolling in any device-based promo.

---

## Security notes

- **Never hard-code your production API token in source control.** Use Xcode's build configuration files, environment variables, or a secrets manager (e.g. `xcconfig`, fastlane `.env`) and inject the token at build time.
- The SDK strips the `Authorization` header value from all internal debug logs. Raw tokens are never printed.
- The API token should be treated as a server secret scoped to your app. Rotate it from **Account → API Access** if it is ever exposed.

---

## Publishing a new version

The package is versioned via **git tags**. Swift Package Manager requires a full three-part semantic version (`MAJOR.MINOR.PATCH`).

### Checklist before tagging

- [ ] Bump `public static let version` in `Jishu.swift` to match the new tag.
- [ ] Update this README's **Current version** badge at the top.
- [ ] Ensure `swift build` and `swift test` both pass with zero errors.
- [ ] Commit all changes.

### Tag and push

```bash
git tag 0.1.4
git push origin 0.1.4
```

Or push all local tags at once:

```bash
git push origin --tags
```

> **Note:** Tags like `1.0` (without a patch component) are **not** recognised by SPM. Always use the full `X.Y.Z` format.

### Creating a GitHub Release (recommended)

After pushing the tag, create a GitHub Release for discoverability and changelogs:

1. Go to your repository on GitHub.
2. Click **Releases → Draft a new release**.
3. Select the tag you just pushed.
4. Write a short changelog and click **Publish release**.

Downstream consumers using `.upToNextMajor(from:)` will pick up the new version automatically on their next package resolution.

---

## Running the tests

### Unit tests (no network required)

```bash
cd Jishu
swift test
```

All tests should pass. The test suite covers:

| Suite | What it tests |
|---|---|
| `DeviceIDStore` | UUID generation, persistence, isolation between suites |
| `AccessResult decoding` | Full response, `matchType: none`, null fields, ISO 8601 dates |
| `AccessCache` | Cache hit/miss, negative result exclusion, expiry, 30-minute cap |
| `JishuClient` | 200 success, 401 no-retry, 500 retry, retry-then-succeed, auth header |
| `Contact` | 201/200 success, 429 error, 500 retry, correct URL and no auth header, body encoding |

### Testing in your Xcode project (local package)

While developing, you can point your app at the local package instead of the published version:

1. In your app project, open **File → Add Package Dependencies…**
2. Click **Add Local…** and select the `Jishu/` directory.
3. Xcode uses your local sources directly — no tagging needed.

To switch back to the published version later, remove the local package and re-add it via the GitHub URL.

### Integration test against staging

Follow the [Staging smoke test](#staging-smoke-test) section above. Configure the SDK with `debugLevel: .verbose` to see the full request/response cycle in the Xcode console.
