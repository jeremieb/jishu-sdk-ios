# Jishu Swift SDK Messaging Doc

This file is the implementation handoff for the separate public Swift SDK repository at:

- `/Users/jeremieberduck/Developer/jishu-sdk-ios`

Repository package name:

- `Jishu`

Import shape:

- `import Jishu`

Primary goal:

- make contact messaging a first-class SDK capability for native iOS apps
- let app developers wire a simple SwiftUI or UIKit form to a `ContactMessage` value and send it to Jishu with minimal setup
- ship an example iOS app that demonstrates the full integration flow

This document is about messaging support. Existing promo-access functionality may remain in the package, but messaging is the new priority capability.

## Product Behavior

The host app is configured with a Jishu `appId`.

The SDK should let the app developer:

1. create a simple contact form view
2. map the entered values into a `ContactMessage`
3. call a single SDK method
4. let the SDK send `POST /api/apps/:appId/contact`

On success:

- the message is stored by Jishu
- the app owner sees it in Dashboard → User Messages
- the app owner may receive a push notification in Jishu client apps

## Locked API Contract

Endpoint:

- `POST /api/apps/:appId/contact`

Base URL rule:

- callers pass the root origin only, for example `https://jishu.page` or `https://staging.jishu.page`
- the SDK appends `/api/apps/:appId/contact`
- reject base URLs that already contain a path component other than `/`

Headers:

- `Content-Type: application/json`
- no auth header for this endpoint

Request body:

```json
{
  "senderEmail": "visitor@example.com",
  "senderName": "Jane Visitor",
  "subject": "Quick question",
  "body": "Hi, I wanted to ask about..."
}
```

Success response:

```json
{ "ok": true }
```

Error shape:

```json
{ "error": "Human-readable message" }
```

Validation rules:

- `senderEmail` is required, valid email, max 255 chars
- `body` is required, max 5000 chars
- `senderName` is optional, max 255 chars
- `subject` is optional, max 255 chars
- endpoint is public, but `appId` must exist server-side
- rate limited per IP hash + app

## Public API

The messaging surface should be extremely small.

Recommended public API:

```swift
public enum Jishu {
    public static func configure(
        baseURL: URL,
        appId: String,
        apiToken: String? = nil,
        environment: String? = nil,
        enableDebugLogs: Bool = false
    )

    public static func sendContactMessage(_ message: ContactMessage) async throws
}
```

Required request model:

```swift
public struct ContactMessage: Sendable {
    public let senderEmail: String
    public let senderName: String?
    public let subject: String?
    public let body: String

    public init(
        senderEmail: String,
        senderName: String? = nil,
        subject: String? = nil,
        body: String
    )
}
```

Recommended error model:

- reuse `JishuError` where reasonable
- add a transport / API error case that can expose the server `{ error }` message safely
- keep configuration errors separate from request errors

Important compatibility note:

- if promo-access APIs remain in the SDK, `apiToken` may still be used by those calls
- messaging itself must not require an API token

## Expected Swift Integration

The intended developer experience should look roughly like this:

```swift
import Jishu
import SwiftUI

struct ContactView: View {
    @State private var email = ""
    @State private var name = ""
    @State private var subject = ""
    @State private var body = ""

    var body: some View {
        Button("Send") {
            Task {
                try await Jishu.sendContactMessage(
                    ContactMessage(
                        senderEmail: email,
                        senderName: name.isEmpty ? nil : name,
                        subject: subject.isEmpty ? nil : subject,
                        body: body
                    )
                )
            }
        }
    }
}
```

That is the bar: the host app should be able to connect a basic view to a message object and send it with one SDK call.

## Implementation Requirements

Suggested additions in the Swift repo:

```text
Sources/Jishu/
  Contact/ContactMessage.swift
  Network/ContactRequest.swift
```

Expected updates:

- `Sources/Jishu/Jishu.swift`
- `Sources/Jishu/Config/JishuConfiguration.swift`
- `Sources/Jishu/Network/JishuClient.swift`
- `Sources/Jishu/Models/JishuError.swift` if needed

Behavior requirements:

- use `URLSession`
- 10 second timeout
- no automatic retry for 4xx responses
- at most 1 retry for transient transport failures or 5xx responses
- never log message body or raw API token in debug output
- validate required fields before sending when it improves developer feedback

## Example App Requirement

The Swift repo already contains an example app. Update it to demonstrate messaging.

Target:

- `/Users/jeremieberduck/Developer/jishu-sdk-ios/App Example`

The example app should include:

- SDK configuration
- a simple contact form screen
- local loading state
- success message
- failure message from thrown SDK error

The example should be minimal and real, not pseudocode hidden in README only.

## Suggested Repo Layout

```text
Package.swift
README.md
Sources/Jishu/
Tests/JishuTests/
App Example/
LICENSE
```

Suggested minimum platform:

- iOS 15+

## Tests

Add tests covering:

- contact request encoding
- success response handling
- API error decoding from `{ error: "..." }`
- missing configuration behavior
- base URL validation

Suggested test files:

```text
Tests/JishuTests/
  ContactMessageEncodingTests.swift
  ContactRequestTests.swift
```

## README Sections

The Swift repo README should include:

1. What Jishu messaging is
2. Installation via Swift Package Manager
3. Configure the SDK
4. Send a contact message from a SwiftUI view
5. Error handling
6. Example app
7. Optional note about promo access if it remains in the package

## First Milestone Checklist

1. Update configuration model so messaging can work without an API token
2. Add `ContactMessage`
3. Add network request for `POST /api/apps/:appId/contact`
4. Add `Jishu.sendContactMessage(_:)`
5. Update the example iOS app with a working contact form
6. Add unit tests for encoding and error handling
7. Update README quickstart for messaging
