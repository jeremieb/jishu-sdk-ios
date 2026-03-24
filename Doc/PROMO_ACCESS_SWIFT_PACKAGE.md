# Promo Access Swift Package Start Doc

This file is the implementation handoff for the separate public Swift SDK repository.

Package name:

- `Jishu`

Import shape:

- `import Jishu`

Primary goal:

- provide a small Swift package that can check Jishu promo access from iOS apps and optionally merge that result with RevenueCat entitlement state

## Locked API Contract

The current server contract is live on staging and should now be treated as the SDK v1 contract.

Endpoint:

- `POST /api/v1/mobile/entitlements/check`

Base URL rule:

- callers pass the root origin only, for example `https://jishu.page` or `https://staging.jishu.page`
- the SDK appends `/api/v1/mobile/entitlements/check`
- reject base URLs that already contain a path component other than `/`

Headers:

- `Authorization: Bearer <apiToken>`
- `Content-Type: application/json`

Request body:

```json
{
  "appId": "app_id",
  "platform": "ios",
  "externalUserId": "customer_123",
  "deviceId": "550e8400-e29b-41d4-a716-446655440000",
  "environment": "staging"
}
```

Response body:

```json
{
  "granted": true,
  "grantId": "grant_id_or_null",
  "matchType": "user",
  "expiresAt": "2026-04-24T12:00:00.000Z",
  "serverTime": "2026-03-24T12:00:00.000Z"
}
```

Notes:

- `platform` is always hardcoded to `"ios"` inside the SDK
- at least one of `externalUserId` or `deviceId` must be sent
- `environment` is optional and may be `production`, `staging`, `testflight`, `internal`, or omitted
- the server may return `matchType = "none"` with `granted = false`

## Public API

Keep the initial public surface small:

```swift
public enum Jishu {
    public static func configure(baseURL: URL, apiToken: String, appId: String, environment: String? = nil, enableDebugLogs: Bool = false)
    public static var displayUserID: String { get }
    public static func checkAccess(externalUserId: String? = nil) async throws -> AccessResult
}
```

Phase 2 optional helper:

```swift
public static func hasAccessWithRevenueCat(entitlementID: String, externalUserId: String? = nil) async throws -> RevenueCatAccessResult
```

Required response model:

```swift
public struct AccessResult: Sendable {
    public let granted: Bool
    public let grantId: String?
    public let matchType: MatchType
    public let expiresAt: Date?
    public let serverTime: Date
}

public enum MatchType: String, Sendable {
    case user
    case device
    case none
}
```

## Identity Rules

Use `deviceId` internally, but expose it to app developers as:

- `Jishu.displayUserID`

Implementation requirements:

- generate a UUID once
- store it in `UserDefaults`
- reuse it on every launch
- never rotate it automatically

Important warning for package docs:

- reinstalling the app creates a new ID
- any active promo grant attached to the old ID stops matching
- `externalUserId` is the preferred mode whenever the customer already has authentication

## Network Behavior

Implementation requirements:

- use `URLSession`
- 10 second request timeout
- no retries for 4xx responses
- at most 1 retry for transient transport failures or 5xx responses
- do not log the raw API token
- debug logging must be opt-in

Caching rule for v1:

- cache only positive responses
- cache until the earlier of:
  - `expiresAt`
  - 5 minutes from fetch time
- do not cache negative responses beyond the current call

## Suggested Package Layout

```text
Sources/Jishu/
  Jishu.swift
  Config/JishuConfiguration.swift
  Identity/DeviceIDStore.swift
  Network/JishuClient.swift
  Models/AccessResult.swift
  Cache/AccessCache.swift
  Support/Logger.swift
```

Tests:

```text
Tests/JishuTests/
  DeviceIDStoreTests.swift
  JishuClientTests.swift
  AccessCacheTests.swift
  AccessResultDecodingTests.swift
```

## RevenueCat Scope

Do not make RevenueCat a hard dependency for the first package cut.

Recommended approach:

- ship the core package first without RevenueCat linkage
- add RevenueCat bridge helpers in a second pass
- if RevenueCat support is added, keep it behind a separate source file or target so the core package remains usable without that dependency

Minimum docs requirement when RevenueCat support is added:

- authenticated apps should use their real stable user ID for both RevenueCat `appUserID` and Jishu `externalUserId`
- unauthenticated apps may use `Jishu.displayUserID`, but docs must warn about reinstall identity loss

## Repo Bootstrap

Suggested repo contents:

```text
Package.swift
README.md
Sources/
Tests/
LICENSE
.gitignore
```

Suggested minimum platforms:

- iOS 15+

Reason:

- async/await support keeps the initial API much cleaner

## README First Draft Sections

The separate public repo should start with these sections:

1. What Jishu promo access is
2. Installation via Swift Package Manager
3. Quickstart
4. `displayUserID` and identity guidance
5. Staging test example
6. RevenueCat integration notes
7. Reinstall limitation warning
8. Security notes for API tokens

## First Milestone Checklist

1. Create package repo and basic `Package.swift`
2. Implement `configure`
3. Implement persistent `displayUserID`
4. Implement `checkAccess(externalUserId:)`
5. Decode live staging response
6. Add unit tests for config validation and decoding
7. Add a tiny sample app or README example

## Staging Smoke Test Target

Use the currently live staging environment:

- base URL: `https://staging.jishu.page`

Manual test flow:

1. create an app in Jishu staging Promo access
2. create a grant for either a `User ID` or `Phone ID`
3. create an API token in Account → API access
4. configure the SDK with staging base URL, token, and app ID
5. call `checkAccess`

Expected success shape:

- `granted == true`
- `matchType == .user` or `.device`
- `expiresAt != nil`

## Non-Goals For First Cut

- StoreKit integration
- DeviceCheck or App Attest
- background refresh
- analytics
- webhooks
- multiple environments per singleton beyond the configured value

## Open Decisions To Keep In Repo README

- whether `Jishu` stays as a static singleton only, or also exposes an instance-based client later
- whether RevenueCat helpers live in the main target or a secondary target
- whether to add a Combine wrapper in addition to async/await
