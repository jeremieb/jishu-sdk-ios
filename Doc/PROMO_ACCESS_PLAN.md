# Promo Access Service Plan

## Goal

Add a paid-user feature that lets app publishers grant temporary access to premium app functionality for specific people without requiring an App Store or Play Store purchase flow for that recipient.

This should be positioned as:

- promo access
- sponsored access
- reviewer / influencer / friend access
- support-granted entitlement

Avoid positioning it as a general-purpose way to evade app store billing rules. The implementation and product language should make it clear that this is a publisher-issued entitlement grant, not an alternate payment rail.

## Policy Reality

### Apple

High risk if this is used as a mass-market substitute for in-app subscriptions for digital features consumed in the iOS app.

Safer cases:

- the app is consumption-only and users sign in to access an account created elsewhere
- the publisher is granting complimentary access, not collecting payment in-app or directing users to external purchase flows
- the app already has an account model where server-side entitlements are normal

Risky cases:

- the app offers digital subscriptions in-app via StoreKit and this feature is marketed as a way around App Store billing
- users can self-serve “bypass” access instead of purchasing
- the app links users to external payment/account flows without the proper entitlement or eligibility

Working assumption for product design:

- allow publishers to grant complimentary access to named users/devices
- do not build consumer-facing purchase redirection into this feature
- keep an audit trail and hard caps to show it is a publisher-controlled exception flow

### Google Play

Lower friction than Apple, but still risky if used to avoid Play Billing for digital goods sold inside a Play-distributed app.

Safer cases:

- the Android app is consumption-only and users sign in to access entitlements created elsewhere
- access is granted by the publisher as a promo or support action
- no in-app flow leads the user to an external payment method unless the app is enrolled in the relevant Google Play program for that region

Risky cases:

- this becomes a normal substitute for Play subscriptions
- the app nudges users to pay outside Play from within the app
- the entitlement appears equivalent to an alternate unmanaged billing system

## Product Direction

Build this as a server-side entitlement grant service, not as a payment bypass service.

Final product name:

- Promo access

Recommended first-version rule set:

- available only to paid Jishu users
- grants are always time-limited
- each grant must target either a `deviceId` or an `externalUserId`
- optional label / note for who the grant is for
- optional environment tag such as `production`, `staging`, `testflight`, `internal`
- all grants are auditable

### RevenueCat compatibility

This feature should explicitly support customers using RevenueCat on iOS and Android.

RevenueCat should be treated as the app-side subscription state layer, while Jishu provides an override signal for promo or sponsored access.

Recommended rule:

- premium access is granted if RevenueCat entitlement is active
- or if Jishu promo access grant is active

This keeps RevenueCat as the primary subscription source of truth while allowing publishers to add time-limited exceptions.

## Identity Strategy

### Important constraint

There is still no universally reliable, permanent phone identifier that survives every reinstall on both iOS and Android and is broadly acceptable for this use case.

For v1, we should deliberately avoid trying to outsmart the platforms.

### Recommended identifier model

Support only two identity modes:

1. `externalUserId`
2. `deviceId`

#### 1. `externalUserId`

Best option when the publisher already has authentication.

Properties:

- stable across reinstall
- stable across device changes if the same user logs in
- easiest to reason about
- lowest policy risk

#### 2. `deviceId`

Best fallback when the publisher has no authentication.

Implementation idea:

- generated once by the SDK as a UUID
- stored in local app storage
- on iOS, stored in `UserDefaults`
- on Android, stored in `SharedPreferences` or `DataStore`

Properties:

- extremely simple to integrate
- easy for support flows because it can be displayed to the end user
- **resets on every reinstall** — this is a permanent structural limitation, not a one-time migration edge case; every time the end user reinstalls the app a new UUID is generated and any existing promo grant becomes unreachable unless the publisher re-grants to the new ID
- should be treated as an app-scoped identifier, not a true device identifier

This means the dashboard label can still say `Phone ID` for non-technical users, but the technical documentation should call it `deviceId` and include a clear warning: "If your user reinstalls the app, their Phone ID will change and any active grant will no longer apply. You will need to create a new grant for the new ID. Use User ID mode if identity continuity across reinstalls matters to your use case."

### Recommended server matching order

The SDK should send whichever identifiers are available (one or both). The server collects all active matching grants across every identifier present in the request, then returns the single grant with the latest `expires_at`.

This means: if the request includes both `externalUserId` and `deviceId`, and active grants exist for both, the server returns whichever expires later — not whichever identifier type is listed first. The matching order (externalUserId, then deviceId) is only a fallback sequence for when one identifier is absent, not a priority ranking when both match.

The server should store hashed lookup values and return only the matched grant outcome, never the stored identifiers.

### RevenueCat mapping

For customers using RevenueCat:

- if they already have authentication, their RevenueCat `appUserID` should be their own stable user ID, and the same value should be used as Jishu `externalUserId`
- if they do not have authentication, the simplest path is to use `Jishu.displayUserID` as the RevenueCat `appUserID`

This gives them one identifier across:

- their app UI
- Jishu promo access grants
- RevenueCat customer records
- support conversations with end users

## Existing Repo Fit

The current codebase already has the right insertion points:

- Worker API routing is centralized in `worker/index.js`
- D1 schema is in `worker/schema.sql`
- dashboard sections are added via `src/platform/Dashboard.jsx`
- platform styling is centralized in `src/styles/platform.css`
- paid access already exists through `user_subscriptions`

This feature should follow the existing platform pattern:

1. new D1 tables in `worker/schema.sql`
2. new Worker handlers before `export default`
3. new routes wired into the fetch handler
4. new dashboard section component
5. optional API docs update in the Swagger spec

## Data Model

### Table: `entitlement_apps`

One record per customer app that wants to use the service.

Suggested columns:

- `id TEXT PRIMARY KEY`
- `owner_user_id TEXT NOT NULL`
- `name TEXT NOT NULL`
- `bundle_id_ios TEXT NOT NULL DEFAULT ''`
- `package_name_android TEXT NOT NULL DEFAULT ''`
- `status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive'))`
- `created_at TEXT NOT NULL`
- `updated_at TEXT NOT NULL`
- `FOREIGN KEY (owner_user_id) REFERENCES users(id) ON DELETE CASCADE`

Purpose:

- identify which customer app is querying entitlements
- scope grants by app
- provide display metadata for dashboard setup

### Table: `entitlement_grants`

Publisher-created time-limited access grants.

Suggested columns:

- `id TEXT PRIMARY KEY`
- `owner_user_id TEXT NOT NULL`
- `app_id TEXT NOT NULL`
- `target_type TEXT NOT NULL CHECK (target_type IN ('device', 'user'))`
- `target_hash TEXT NOT NULL`
- `target_last4 TEXT NOT NULL DEFAULT ''`
- `platform TEXT NOT NULL DEFAULT 'any' CHECK (platform IN ('any', 'ios', 'android'))`
- `duration_days INTEGER NOT NULL` — records the original grant duration at creation time; treated as immutable after creation; after an `extend` operation only `expires_at` is updated, so `duration_days` reflects the original grant, not the total extended duration; the dashboard should derive displayed duration from `expires_at - starts_at` rather than from this column
- `starts_at TEXT NOT NULL`
- `expires_at TEXT NOT NULL`
- `environment TEXT NOT NULL DEFAULT '' CHECK (environment IN ('', 'production', 'staging', 'testflight', 'internal'))`
- `label TEXT NOT NULL DEFAULT ''`
- `note TEXT NOT NULL DEFAULT ''`
- `status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked'))`
- `created_at TEXT NOT NULL`
- `updated_at TEXT NOT NULL`
- `revoked_at TEXT`
- `FOREIGN KEY (owner_user_id) REFERENCES users(id) ON DELETE CASCADE`
- `FOREIGN KEY (app_id) REFERENCES entitlement_apps(id) ON DELETE CASCADE`

Indexes:

- index on `owner_user_id`
- index on `app_id`
- index on `(app_id, target_type, target_hash, status)` — used by the SDK check query
- index on `expires_at` — used for the dashboard list and future cleanup sweeps

Note: grant expiry is evaluated at runtime using `starts_at <= datetime('now') AND expires_at > datetime('now')`, not by writing a status change. There is no scheduled job that flips grants to an `expired` state. The dashboard "expired" filter is a display concept only, derived from `expires_at`. A future Phase 3 cleanup cron can hard-delete or archive old rows using the `expires_at` index.

### Table: `entitlement_grant_events`

Audit log.

Suggested columns:

- `id TEXT PRIMARY KEY`
- `grant_id TEXT NOT NULL`
- `event_type TEXT NOT NULL`
- `actor_user_id TEXT`
- `metadata_json TEXT NOT NULL DEFAULT '{}'`
- `created_at TEXT NOT NULL`
- `FOREIGN KEY (grant_id) REFERENCES entitlement_grants(id) ON DELETE CASCADE`

Event types (mutations only — reads go to `entitlement_check_logs`):

- `created`
- `revoked`
- `extended`

### Table: `entitlement_check_logs`

Optional metering and debugging.

Suggested columns:

- `id INTEGER PRIMARY KEY AUTOINCREMENT`
- `app_id TEXT NOT NULL`
- `grant_id TEXT`
- `match_type TEXT NOT NULL DEFAULT ''`
- `granted INTEGER NOT NULL DEFAULT 0`
- `platform TEXT NOT NULL DEFAULT ''`
- `created_at TEXT NOT NULL DEFAULT (datetime('now'))`
- `FOREIGN KEY (app_id) REFERENCES entitlement_apps(id) ON DELETE CASCADE`
- `FOREIGN KEY (grant_id) REFERENCES entitlement_grants(id) ON DELETE SET NULL`

This can be sampled if volume becomes high. At scale (e.g. 100 publishers × 1k checks/day) the table grows ~100k rows/day. D1 production databases are limited to 10 GB. A Phase 3 scheduled Worker (`scheduled` event in `wrangler.toml`) should delete rows older than 90 days using the `created_at` column. Add an index on `created_at` if that sweep is implemented.

## Access Rules

### Who can use it

Only customers with an active paid Jishu subscription.

Server-side rule:

- allow if `user_subscriptions.tier_id IS NOT NULL`
- also allow if `billing_override = 'free'` for internal/manual exceptions
- deny for unpaid users

### Suggested commercial limits for v1

- max 3 apps per customer initially
- max 100 active grants per customer initially
- max duration 365 days
- max note length 500 chars
- default duration presets: 7, 30, 90, 180, 365 days

Hard limits reduce abuse and make App Review positioning easier.

## API Surface

### Versioning

The Promo access API should be versioned from the first release.

**Two separate concepts — do not conflate them:**

- **Product label:** `API v1.0` — used in documentation, changelogs, and SDK release notes; minor increments (v1.1, v1.2) do not change the URL path
- **URL path prefix:** `/api/v1` — uses the major version only; only a breaking change triggers a new path (`/api/v2`)

This means the path `/api/v1` covers the entire v1.x lifecycle. Do not create a `/api/v1.0/` path — that is incorrect.

Recommended versioning approach:

- URL path encodes the major version only (`/api/v1`)
- additive, non-breaking changes (new optional fields, new optional query params) are allowed within the same major version without a path bump
- breaking changes (removed fields, changed field types, changed behavior, removed endpoints) require a new major path version
- dashboard routes (`/api/v1/entitlements/...`) are session-authenticated internal APIs — they share the version prefix for consistency but do not carry the same external stability guarantee as the SDK check endpoint
- the SDK check endpoint (`/api/v1/mobile/entitlements/check`) is the true external public contract and must be treated with the highest stability priority

**Deprecation policy:** SDKs are compiled into shipped apps and cannot be updated without an app release. When a breaking `/api/v2` is introduced, `/api/v1` must remain operational for a minimum of 12 months from the v2 launch date, with advance notice to customers at least 90 days before shutdown. The SDK major version bump to v2.x is the signal to customers to migrate.

### Dashboard-authenticated customer APIs

#### `GET /api/v1/entitlements/apps`

List the customer’s registered apps.

#### `POST /api/v1/entitlements/apps`

Create a registered app.

Payload:

- `name`
- `bundleIdIos`
- `packageNameAndroid`

#### `GET /api/v1/entitlements/grants?appId=...`

List grants for one app. Add `status` filter support (`active`, `revoked`, or omit for all) so the dashboard tabs can filter server-side.

Pagination: deferred for v1 as an early-stage simplification. The 100 active grant cap bounds live grants, but revoked and elapsed grants accumulate unboundedly over time, so the response size is not truly capped. For v1 this is acceptable given expected low usage volume. Pagination (`limit` + `cursor`) should be added before any public-scale launch or when the dashboard list becomes noticeably slow in testing.

#### `POST /api/v1/entitlements/grants`

Create a grant.

Payload:

- `appId`
- `targetType` = `device` or `user`
- `targetValue`
- `platform`
- `durationDays`
- `environment` optional — one of `production`, `staging`, `testflight`, `internal`; defaults to empty (untagged)
- `label`
- `note`
- `startsAt` optional

#### `POST /api/v1/entitlements/grants/:grantId/revoke`

Revoke an active grant.

#### `POST /api/v1/entitlements/grants/:grantId/extend`

Extend expiry.

Payload:

- `durationDays`

Extension rule:

- only `active` grants can be extended; return 400 if `status = 'revoked'`
- if `expires_at` is in the future: add `durationDays` to the current `expires_at`, preserving remaining access
- if `expires_at` is in the past but `status` is still `active` (elapsed but not revoked): extend from `now()` so the grant becomes active immediately
- update `expires_at` and `updated_at`; do not change `duration_days` (it records the original grant duration)

#### `GET /api/v1/entitlements/usage`

Return summary counts for dashboard cards.

### SDK-facing app API

#### `POST /api/v1/mobile/entitlements/check`

Authenticated with the existing user API token from Account → API access.

The upcoming mobile app can reuse the same token infrastructure already present in the project via `api_tokens`.

Request payload:

- `externalUserId` optional
- `deviceId` optional
- `appId` required
- `platform` required
- `appVersion` optional
- `sdkVersion` optional

Response payload:

- `granted: boolean`
- `grantId: string | null`
- `matchType: 'user' | 'device' | 'none'`
- `expiresAt: string | null`
- `serverTime: string`

Do not return stored identifiers.

The server-side grant lookup runs up to two queries (one per identifier present in the request) and selects the best result:

```sql
SELECT * FROM entitlement_grants
WHERE app_id = ?
  AND target_type = ?
  AND target_hash = ?
  AND status = 'active'
  AND starts_at <= datetime('now')
  AND expires_at > datetime('now')
ORDER BY expires_at DESC
LIMIT 1
```

Run once for `externalUserId` (if provided) and once for `deviceId` (if provided), then return whichever result has the later `expires_at`. This ensures the user gets the longest available access regardless of which identifier type was matched.

### RevenueCat-aware SDK behavior

The Jishu SDK should support two app-side integration modes:

1. standalone Jishu gating
2. RevenueCat + Jishu combined gating

In RevenueCat mode, the app would:

1. ask RevenueCat for the relevant entitlement status
2. ask Jishu whether promo access is active
3. unlock premium UI if either source returns access

This should be implemented in the SDK helper layer so customers do not have to rewrite the same merge logic on both platforms.

## Worker Implementation Plan

### New helpers in `worker/index.js`

- `requirePaidCustomer(request, env)`
- `hashEntitlementTarget(targetType, value)` — normalization is type-specific before hashing: for `device` targets, lowercase then trim (UUIDs are case-insensitive so this is safe); for `user` targets, trim whitespace only — do not lowercase, because external user IDs are opaque strings that may be case-sensitive in the publisher's auth system; then compute HMAC-SHA256 keyed with `ENTITLEMENT_HASH_SECRET`; this normalization must be applied identically on the dashboard grant-create path and the SDK check path; set the secret via `wrangler secret put ENTITLEMENT_HASH_SECRET --env staging` (and production)
- `maskIdentifier(value)` — return last 4 chars only
- `normalizeEntitlementPlatform(value)`
- `validateGrantPayload(body)`

Note: bearer token → `user_id` resolution already exists in `worker/index.js` (lines ~582–592 inside `readAuthenticatedUser`). Do not create a duplicate implementation — extract or reuse that existing logic for the SDK route auth.

### Route families

Dashboard routes:

- authenticated with `requireAuthenticatedUser`
- gated by a new paid-user rule, not admin-only
- ownership checks on every app and grant

SDK route:

- existing bearer token auth via `api_tokens`
- rate-limited
- no dashboard session required
- the `appId` in the request must belong to the account that owns the API token — verify `entitlement_apps.owner_user_id = tokenUserId` before running the grant lookup, otherwise any valid token could query any publisher's grants

**API token blast radius — important:** the existing `api_tokens` model is user-scoped, not app-scoped. One leaked token exposes all apps owned by that customer, and revoking it breaks all apps at once. For v1 this is acceptable, but the docs and dashboard should clearly recommend creating one dedicated token per shipped app. The Tab 1 quickstart should prompt: "Create a token specifically for this app — do not reuse a token across multiple apps." A future improvement is to add an optional `app_id` scope column to `api_tokens` so a token can be restricted to a single app at the database level.

### Recommended fetch handler wiring

Add a new route family near the other account/product APIs:

- `GET /api/v1/entitlements/apps`
- `POST /api/v1/entitlements/apps`
- `GET /api/v1/entitlements/grants`
- `POST /api/v1/entitlements/grants`
- `POST /api/v1/entitlements/grants/:id/revoke`
- `POST /api/v1/entitlements/grants/:id/extend`
- `GET /api/v1/entitlements/usage`
- `POST /api/v1/mobile/entitlements/check`

Versioning implementation note:

- keep the unversioned routes unused for this feature
- the SDKs should hardcode the `/api/v1` prefix
- Swagger docs should group these endpoints under `Promo access API v1.0`

## Dashboard UX Plan

### New section

Create:

- `src/platform/sections/EntitlementsSection.jsx`

Add to `Dashboard.jsx` main nav for all logged-in users, not only admins.

**Behavior for unpaid users:** show the nav item and section to all logged-in users, but replace the section content with an upsell prompt for users who do not have an active paid subscription. Do not hide the nav item entirely — feature discovery matters. The upsell state should explain what Promo access does and link to the Plans page.

**Implementation rule:** the section component checks subscription status on mount. If `billingOverride !== 'free'` and `tierIsNull`, render the upsell instead of the tabs. All API routes still enforce the paid-user gate server-side regardless of what the client renders.

Recommended label:

- `Promo access`

### Section layout

Tab 1: Apps

- register iOS / Android app identifiers
- show which existing API token to use from settings, with a prompt to create a dedicated token for this app and not reuse one across multiple apps
- show quickstart code blocks

Tab 2: Grants

- app picker
- target type picker: `Phone ID` or `User ID`
- target value input
- duration picker
- platform picker
- create grant
- active / expired / revoked filters
- revoke and extend actions

Tab 3: Docs

- integration steps
- identifier recommendations
- example SDK requests
- API versioning and upgrade policy
- App Store / Play policy caveats
- RevenueCat integration examples

### UX details

- explain clearly that `User ID` is preferred if the customer already has login
- explain that `Phone ID` is a UUID generated and stored by the SDK locally
- never display full stored device IDs after creation
- show partial masked value only
- add a short RevenueCat note explaining when to use `externalUserId` vs `Jishu.displayUserID`

## SDK Deliverables

### Swift Package

Suggested package name:

- `Jishu`

Desired integration:

- `import Jishu`

Suggested public API:

- `Jishu.configure(baseURL:apiToken:appId:)` — `baseURL` is the root origin only, e.g. `https://jishu.page`; the SDK appends `/api/v1/mobile/entitlements/check` internally; customers must not include a path component in `baseURL`
- `Jishu.displayUserID`
- `Jishu.checkAccess(externalUserId:)`
- `Jishu.hasAccessWithRevenueCat(entitlementID:externalUserId:)`

Responsibilities:

- generate and persist `deviceId` as a UUID
- store it in `UserDefaults`
- expose it directly for support or invitation flows through `Jishu.displayUserID`
- call Jishu entitlement check endpoint using the existing per-user API token
- call the versioned Jishu entitlement endpoint at `/api/v1/mobile/entitlements/check`
- the `platform` field sent to the server is always hardcoded to `"ios"` by the Swift SDK — it is not a public configure parameter
- cache positive result briefly with expiry awareness
- provide a convenience helper that combines RevenueCat entitlement state with Jishu promo access

Suggested RevenueCat integration pattern:

- `import Jishu`
- `import RevenueCat`
- if authenticated: configure RevenueCat with the app's real user ID, and pass the same value to `Jishu.checkAccess(externalUserId:)`
- if unauthenticated: configure RevenueCat with `Jishu.displayUserID`

### Kotlin package

Suggested artifact/module name:

- `jishu`

Desired integration:

- equivalent of `import Jishu`

Suggested public API:

- `Jishu.configure(baseUrl, apiToken, appId)` — `baseUrl` is the root origin only, e.g. `https://jishu.page`; the SDK appends `/api/v1/mobile/entitlements/check` internally; customers must not include a path component in `baseUrl`
- `Jishu.displayUserID`
- `Jishu.checkAccess(externalUserId: String?)`
- `Jishu.hasAccessWithRevenueCat(entitlementId: String, externalUserId: String?)`

Responsibilities:

- generate and persist `deviceId` as a UUID
- store it in `SharedPreferences` or `DataStore`
- expose it directly through `Jishu.displayUserID`
- call Jishu entitlement check endpoint using the existing per-user API token
- call the versioned Jishu entitlement endpoint at `/api/v1/mobile/entitlements/check`
- the `platform` field sent to the server is always hardcoded to `"android"` by the Kotlin SDK — it is not a public configure parameter
- cache result briefly
- provide a convenience helper that combines RevenueCat entitlement state with Jishu promo access

### Minimum RevenueCat SDK versions

The RevenueCat integration examples use APIs that require:

- iOS: RevenueCat `purchases-ios` 4.0 or later (`Purchases.shared.customerInfo()` as async/await)
- Android: RevenueCat `purchases-android` 5.0 or later (`awaitCustomerInfo()` coroutine extension)

Customers on older versions must use the callback-based APIs and adapt the ViewModel examples accordingly. The docs should call this out.

### Shared SDK behavior

- request timeout and retry policy
- offline fallback using short-lived cached success only
- no secrets embedded beyond the existing user API token intended for mobile/API usage
- explicit debug logging toggle
- optional RevenueCat bridge helpers so customers can adopt the feature with minimal code changes

### RevenueCat integration plan

Support the following customer setups:

#### Setup A: Customer already has auth

Recommended flow:

1. app configures RevenueCat with its own stable user ID
2. app calls Jishu with that same ID as `externalUserId`
3. publisher creates Jishu grants by `User ID`

Benefits:

- no reinstall issue
- works across devices
- cleanest support flow

#### Setup B: Customer has no auth and already uses RevenueCat anonymous users

Recommended migration:

1. app adopts `Jishu.displayUserID`
2. on first launch after SDK adoption, call `Purchases.shared.logIn(Jishu.displayUserID)` — this aliases the existing RevenueCat anonymous ID (`$RCAnonymousID:...`) with the new stable Jishu UUID so purchase history is preserved; simply re-configuring with a new `appUserID` without calling `logIn()` will lose existing subscribers' entitlements
3. app can then configure RevenueCat with `Jishu.displayUserID` as the `appUserID` for new installs
4. publisher creates Jishu grants by `Phone ID`

Benefits:

- one visible identifier across both systems
- easier support
- easier manual gifting

Tradeoff:

- **reinstall identity loss is permanent and ongoing, not just a migration concern** — after Setup B, every future reinstall generates a new Jishu UUID, which means the RevenueCat `appUserID` changes, RevenueCat purchase history becomes unlinked, and any active Jishu grant stops matching; the `logIn()` aliasing step only handles the one-time migration from anonymous IDs, it does not solve the ongoing reinstall problem
- `logIn()` aliasing is a one-time migration cost; the docs should flag this clearly for existing RevenueCat customers
- publishers using Setup B should be clearly advised that `externalUserId` mode (Setup A) is the only path to reliable identity continuity; Setup B is suitable only for use cases where reinstall identity loss is acceptable (e.g. short-lived promo codes for new installs, internal testing, one-time influencer access)

#### Setup C: Existing RevenueCat app wants a soft rollout

Recommended flow:

1. leave existing RevenueCat setup unchanged
2. send `Jishu.displayUserID` to Jishu only
3. use Jishu promo access as a separate exception path
4. optionally later align RevenueCat `appUserID` with Jishu ID for new installs only

Benefits:

- less migration risk
- lets customers adopt promo access without reworking their RevenueCat identity model immediately

### ViewModel guidance

To make adoption easy, the SDK and docs should recommend a single premium-access view model per app.

That view model should be the only place where RevenueCat state and Jishu promo access state are merged.

Recommended rule:

- app screens should not query RevenueCat directly
- app screens should not query Jishu directly
- app screens should read a single `hasPremiumAccess` state from the view model

Suggested state:

- `isLoading`
- `hasRevenueCatEntitlement`
- `hasJishuPromoAccess`
- `hasPremiumAccess`
- `premiumSource`
- `expiresAt`
- `lastError`

Suggested `premiumSource` values:

- `revenuecat`
- `jishu`
- `both`
- `none`

Suggested lifecycle:

1. configure RevenueCat
2. configure Jishu
3. fetch RevenueCat `CustomerInfo`
4. fetch Jishu access result
5. merge both into one premium-access state
6. refresh when app becomes active
7. refresh after purchase, restore, login, logout, or account switch

### Merge logic

Recommended merge logic:

- `hasRevenueCatEntitlement = RevenueCat entitlement is active`
- `hasJishuPromoAccess = Jishu grant is active`
- `hasPremiumAccess = hasRevenueCatEntitlement || hasJishuPromoAccess`

Recommended precedence for display and debugging:

- if both are true, set source to `both`
- if only RevenueCat is true, set source to `revenuecat`
- if only Jishu is true, set source to `jishu`
- otherwise set source to `none`

Recommended expiry behavior:

- if source is `jishu`, expose the Jishu `expiresAt`
- if source is `revenuecat`, let the app rely on RevenueCat entitlement state rather than trying to normalize store expiry manually
- if both are true, prefer showing the Jishu promo expiry only in support/debug screens, not as the main subscription expiry UI

### Swift ViewModel example shape

The docs should include a lightweight example such as:

```swift
import Foundation
import Combine
import Jishu
import RevenueCat

@MainActor
final class PremiumAccessViewModel: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var hasRevenueCatEntitlement = false
    @Published private(set) var hasJishuPromoAccess = false
    @Published private(set) var hasPremiumAccess = false
    @Published private(set) var premiumSource: PremiumSource = .none
    @Published private(set) var jishuExpiresAt: Date?
    @Published private(set) var lastError: String?

    enum PremiumSource {
        case revenuecat
        case jishu
        case both
        case none
    }

    func refresh(externalUserId: String?, entitlementId: String) async {
        isLoading = true
        defer { isLoading = false }
        lastError = nil

        do {
            async let customerInfo = Purchases.shared.customerInfo()
            async let jishuAccess = Jishu.checkAccess(externalUserId: externalUserId)

            let info = try await customerInfo
            let access = try await jishuAccess

            let hasRC = info.entitlements[entitlementId]?.isActive == true
            let hasJishu = access.granted

            hasRevenueCatEntitlement = hasRC
            hasJishuPromoAccess = hasJishu
            hasPremiumAccess = hasRC || hasJishu
            jishuExpiresAt = access.expiresAt

            if hasRC && hasJishu { premiumSource = .both }
            else if hasRC { premiumSource = .revenuecat }
            else if hasJishu { premiumSource = .jishu }
            else { premiumSource = .none }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
```

### Kotlin ViewModel example shape

The docs should include the Android equivalent:

```kotlin
class PremiumAccessViewModel : ViewModel() {
    var isLoading by mutableStateOf(false)
        private set
    var hasRevenueCatEntitlement by mutableStateOf(false)
        private set
    var hasJishuPromoAccess by mutableStateOf(false)
        private set
    var hasPremiumAccess by mutableStateOf(false)
        private set
    var premiumSource by mutableStateOf(PremiumSource.NONE)
        private set
    var jishuExpiresAt by mutableStateOf<String?>(null)
        private set
    var lastError by mutableStateOf<String?>(null)
        private set

    enum class PremiumSource { REVENUECAT, JISHU, BOTH, NONE }

    fun refresh(externalUserId: String?, entitlementId: String) {
        viewModelScope.launch {
            isLoading = true
            lastError = null
            try {
                val customerInfo = Purchases.sharedInstance.awaitCustomerInfo()
                val jishuAccess = Jishu.checkAccess(externalUserId)

                val hasRC = customerInfo.entitlements[entitlementId]?.isActive == true
                val hasJishu = jishuAccess.granted

                hasRevenueCatEntitlement = hasRC
                hasJishuPromoAccess = hasJishu
                hasPremiumAccess = hasRC || hasJishu
                jishuExpiresAt = jishuAccess.expiresAt

                premiumSource = when {
                    hasRC && hasJishu -> PremiumSource.BOTH
                    hasRC -> PremiumSource.REVENUECAT
                    hasJishu -> PremiumSource.JISHU
                    else -> PremiumSource.NONE
                }
            } catch (t: Throwable) {
                lastError = t.message
            } finally {
                isLoading = false
            }
        }
    }
}
```

The SDK docs should provide these ViewModel examples as the primary integration pattern. The `hasAccessWithRevenueCat(entitlementID:externalUserId:)` helper is a convenience shortcut for apps that want a single boolean without managing a full ViewModel — it runs the same merge logic internally. The ViewModel pattern is preferred for any app that needs to display expiry, source, or loading state.

### What app developers should do for premium features

The docs should give customers a very explicit app architecture recommendation.

#### 1. Define premium features centrally

Customers should create one central list of premium capabilities in their app, for example:

- premium chat
- premium export
- premium themes
- premium generation credits
- premium analytics

They should avoid sprinkling random entitlement checks around the app.

#### 2. Gate features from one access layer

Customers should expose methods like:

- `canUsePremiumChat`
- `canExport`
- `canAccessTheme(themeId)`

Those methods should read from the premium-access view model, not from RevenueCat directly.

#### 3. Separate purchase UI from feature gating

Recommended rule:

- feature access is determined by `hasPremiumAccess`
- purchase screens are shown only when `hasPremiumAccess == false`

That keeps gifting, manual grants, RevenueCat purchases, and restores all working through the same gate.

#### 4. Refresh access at the right times

Customers should refresh the view model:

- on app launch
- when the app enters foreground
- after a successful purchase
- after restore purchases
- after login
- after logout
- after account switch

#### 5. Show the right UI depending on source

Recommended UI behavior:

- if `premiumSource == revenuecat`, show normal subscription management UI
- if `premiumSource == jishu`, show premium features as unlocked but do not imply there is a store subscription
- if `premiumSource == both`, prefer normal premium UX and avoid confusing duplicate status messaging

#### 6. Keep support UX simple

Customers should expose the current ID somewhere in settings/support UI:

- `Jishu.displayUserID`

That allows an end user to send their ID to the app publisher so the publisher can create a promo grant quickly.

#### 7. Keep server-backed premium features protected

If the customer app has its own backend, premium checks should not live only in the client.

Recommended rule:

- client uses the view model for UX
- backend rechecks entitlement or promo access before performing premium server actions

This matters for features like:

- exports
- AI generation
- private API access
- cloud sync upgrades

#### 8. Prefer one premium entitlement in RevenueCat

For simpler apps, customers should usually have a single RevenueCat entitlement such as `pro`.

That maps cleanly to one app-level rule:

- unlocked by active RevenueCat entitlement
- or unlocked by active Jishu promo access

If a customer has multiple premium tiers, they can still use the same pattern, but the docs should start with the single-entitlement case first.

## Security Model

### Store only hashed targets

Do not store raw device IDs or raw external user IDs in D1.

Store:

- normalized value hash for lookup — normalization is type-specific: `device` targets are lowercased then trimmed (UUIDs are case-insensitive); `user` targets are trimmed only (external user IDs may be case-sensitive); then compute HMAC-SHA256 keyed with `ENTITLEMENT_HASH_SECRET`; this exact normalization must be applied identically on both the dashboard grant-create path and the SDK check path; set the secret via `npx wrangler secret put ENTITLEMENT_HASH_SECRET --env staging` and `--env production`; do not use unsalted SHA-256 since device UUIDs have a small search space and can be brute-forced if the hash is ever exposed
- short masked suffix for support UX only (last 4 chars of the original value)

### API token handling

- reuse the existing `api_tokens` system already present in the project
- customer creates the token in Account → API access
- SDK uses that token as bearer auth for entitlement checks
- dashboard docs should point users to the existing token management flow rather than creating a second credential system

### Abuse controls

- per-app rate limits on SDK checks
- max active grants per account
- audit log for every grant mutation
- suspicious volume alerts later

## Documentation Plan

Update dashboard docs and API docs with:

- API v1.0 path prefix and versioning policy
- policy-safe framing
- iOS identifier limitations
- Android identifier limitations
- recommended integration path with auth
- fallback path without auth
- RevenueCat quickstart for both platforms
- RevenueCat identity mapping guidance

## Rollout Plan

### Phase 1

- D1 schema
- Worker APIs
- dashboard section
- manual app registration
- manual grant create / revoke / extend

### Phase 2

- Swift package
- Kotlin package
- dashboard quickstart docs
- Swagger / API docs
- RevenueCat helper examples
- API v1.0 documentation and migration notes

### Phase 3

- analytics and usage charts
- grant templates
- CSV import
- webhooks
- optional DeviceCheck support on iOS
- deeper RevenueCat migration helpers for customers moving away from anonymous users

### Final Phase: Marketing and Launch

This feature will need careful positioning. The product value is real, but the messaging must stay away from "bypass the stores" language.

Recommended marketing framing:

- give premium access instantly
- invite friends, testers, creators, and influencers in seconds
- grant promo access without coupon codes or manual subscription juggling
- support gifted access, press access, and customer support exceptions
- works with RevenueCat and your existing subscription setup

Messaging to avoid:

- bypass App Store subscriptions
- avoid Apple billing
- avoid Google billing
- pay outside the stores
- replace StoreKit or Play Billing

What we should explain to users:

- Jishu adds a promo-access layer on top of their normal subscription system
- they can grant temporary premium access to a specific user ID or app-generated device ID
- RevenueCat users can combine their existing entitlement checks with Jishu in one view model
- this is best for testers, friends, influencers, support cases, giveaways, and temporary VIP access
- user IDs are preferred when the app already has authentication
- device IDs are the fallback when the app has no authentication

What we should add to the existing landing page:

- a new feature block in the platform/product section for `Promo access`
- a short explanation that this works with native apps, subscriptions, and RevenueCat
- a compact three-step explainer:
  1. install the SDK
  2. share the displayed ID or use your own user ID
  3. grant temporary premium access from the dashboard
- a concrete use-cases strip:
  - invite influencers
  - unlock beta testers
  - gift premium access
  - help support users fast
- a small developer credibility section:
  - Swift package
  - Kotlin package
  - RevenueCat-friendly
  - simple ViewModel integration
- a dashboard screenshot or mockup showing grant creation
- a code snippet teaser showing `import Jishu` and `Jishu.displayUserID`
- a note that the feature is designed as promo access, not a replacement for app store billing

Recommended CTA options on the landing page:

- `Set up promo access`
- `Grant premium access in minutes`
- `Works with RevenueCat`

Recommended launch content:

- one landing page section
- one dedicated docs page
- one short demo video or GIF of the dashboard flow
- one technical tutorial for Swift
- one technical tutorial for Kotlin / Android
- one RevenueCat integration tutorial

Recommended proof points to highlight:

- works on iOS and Android
- no custom backend required for client-side feature gating
- existing RevenueCat apps can adopt it incrementally
- support teams can grant access without touching App Store Connect or Play Console

Success metrics for launch:

- number of paid users who register at least one app
- number of active apps using the entitlement check API
- number of grants created per active account
- conversion from landing page visits to docs views
- conversion from docs views to first app registration
- percentage of adopting customers using the RevenueCat path

## Testing Plan

### Worker / API

- paid user can create app
- unpaid user is rejected
- owner can create, list, revoke, extend grants
- non-owner cannot access another user’s apps or grants
- expired grants do not return `granted: true`
- SDK route matches correct identifier precedence
- all Promo access endpoints are served only under `/api/v1`

### Dashboard

- nav item visible to all logged-in users
- unpaid user sees upsell prompt instead of tabs
- paid user sees full section with tabs
- all API routes reject unpaid users with 403 regardless of client state
- grant form validation works
- docs correctly reference existing API token flow and recommend a dedicated per-app token

### SDK

iOS:

- UUID `deviceId` persists across launches in `UserDefaults`
- check endpoint handles offline / timeout behavior
- RevenueCat merge helper returns access when either RevenueCat entitlement or Jishu grant is active

Android:

- UUID `deviceId` persists across launches in local storage
- reinstall reset behavior is documented
- RevenueCat merge helper returns access when either RevenueCat entitlement or Jishu grant is active

## Recommended Implementation Order

1. Add schema tables and indexes in `worker/schema.sql`
2. Add Worker helpers and customer routes in `worker/index.js`
3. Add SDK route using existing API token auth in `worker/index.js`
4. Add dashboard nav and `EntitlementsSection.jsx`
5. Add CSS in `src/styles/platform.css`
6. Add `/api/v1` route wiring and API versioning docs
7. Add RevenueCat integration docs and helper APIs
8. Build Swift Package
9. Build Kotlin package
10. Test on staging

## Open Decisions

1. Final UI wording: whether to expose `Phone ID` everywhere or use `Device ID` in technical contexts
2. Whether to allow multiple active grants per same target and app, or enforce one active grant per target — recommended default: allow multiple, but the check query always returns the one with the latest `expires_at` so the behavior is deterministic; the dashboard should warn if a grant already exists for the same target
3. Whether grant checks should be logged fully or sampled
4. Whether SDK packages live inside this monorepo or separate repos
5. Whether the RevenueCat helper should be an optional submodule or part of the default `Jishu` surface

## Recommendation

Proceed with this feature only if we position and document it as a publisher-controlled complimentary entitlement service.

Do not market it as a way to avoid App Store or Play billing.

The safest technical product shape is:

- prefer `externalUserId`
- support a locally stored UUID `deviceId` as the no-auth fallback
- expose the UUID directly through the SDK as `Jishu.displayUserID`
- reuse the existing per-user API token system for SDK authentication
- make RevenueCat integration a first-class path by aligning RevenueCat `appUserID` with Jishu identifiers where practical
- keep all entitlements time-limited, auditable, and owner-scoped
