# Jishu iOS SDK

A lightweight Swift package that checks [Jishu](https://jishu.page) promo access from iOS apps, with an optional bridge for RevenueCat entitlements.

- **Current version:** `1.0.0`
- **Minimum platform:** iOS 15
- **Swift:** 6.0+

---

## Table of Contents

1. [What is Jishu promo access?](#what-is-jishu-promo-access)
2. [Installation](#installation)
3. [Quickstart](#quickstart)
4. [User identity and `displayUserID`](#user-identity-and-displayuserid)
5. [Staging smoke test](#staging-smoke-test)
6. [RevenueCat integration](#revenuecat-integration)
7. [Reinstall limitation](#reinstall-limitation)
8. [Security notes](#security-notes)
9. [Publishing a new version](#publishing-a-new-version)
10. [Running the tests](#running-the-tests)

---

## What is Jishu promo access?

Jishu promo access lets you grant specific users or devices early or exclusive access to your app — without going through the App Store review cycle. You create grants in the Jishu dashboard (by user ID, device ID, or phone ID) and this SDK checks at runtime whether the current user holds an active grant.

---

## Installation

### Swift Package Manager (Xcode)

1. In Xcode open **File → Add Package Dependencies…**
2. Paste the repository URL:
   ```
   https://github.com/YOUR_ORG/jishu-sdk-ios
   ```
3. Select **Up to Next Major Version** starting from `1.0.0`.
4. Add **Jishu** to your app target.

### Swift Package Manager (Package.swift)

```swift
dependencies: [
    .package(url: "https://github.com/YOUR_ORG/jishu-sdk-ios", from: "1.0.0"),
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

---

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
    enableDebugLogs: true         // prints request/response info to console
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
git tag 1.0.0
git push origin 1.0.0
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

All 15 tests should pass. The test suite covers:

| Suite | What it tests |
|---|---|
| `DeviceIDStore` | UUID generation, persistence, isolation between suites |
| `AccessResult decoding` | Full response, `matchType: none`, null fields, ISO 8601 dates |
| `AccessCache` | Cache hit/miss, negative result exclusion, expiry, 5-minute cap |
| `JishuClient` | 200 success, 401 no-retry, 500 retry, retry-then-succeed, auth header |

### Testing in your Xcode project (local package)

While developing, you can point your app at the local package instead of the published version:

1. In your app project, open **File → Add Package Dependencies…**
2. Click **Add Local…** and select the `Jishu/` directory.
3. Xcode uses your local sources directly — no tagging needed.

To switch back to the published version later, remove the local package and re-add it via the GitHub URL.

### Integration test against staging

Follow the [Staging smoke test](#staging-smoke-test) section above. Configure the SDK with `enableDebugLogs: true` to see the raw request/response cycle in the Xcode console.
