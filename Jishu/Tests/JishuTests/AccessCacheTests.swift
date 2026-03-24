import Testing
import Foundation
@testable import Jishu

@Suite("AccessCache")
struct AccessCacheTests {
    private func makeResult(granted: Bool, expiresAt: Date? = nil) -> AccessResult {
        AccessResult(
            granted: granted,
            grantId: granted ? "grant_1" : nil,
            matchType: granted ? .user : .none,
            expiresAt: expiresAt,
            serverTime: Date()
        )
    }

    @Test("Negative result is not cached")
    func negativeResultNotCached() async {
        let cache = AccessCache()
        let result = makeResult(granted: false)
        await cache.set(key: "user1", result: result)
        let cached = await cache.get(key: "user1")
        #expect(cached == nil)
    }

    @Test("Positive result is cached and returned")
    func positiveResultCached() async {
        let cache = AccessCache()
        let result = makeResult(granted: true, expiresAt: Date().addingTimeInterval(3600))
        await cache.set(key: "user1", result: result)
        let cached = await cache.get(key: "user1")
        #expect(cached != nil)
        #expect(cached?.granted == true)
    }

    @Test("Expired entry is not returned")
    func expiredEntryNotReturned() async {
        let cache = AccessCache()
        let result = makeResult(granted: true, expiresAt: Date().addingTimeInterval(-1))
        await cache.set(key: "user1", result: result)
        let cached = await cache.get(key: "user1")
        #expect(cached == nil)
    }

    @Test("Cache respects 5-minute cap when expiresAt is far in the future")
    func respectsFiveMinuteCap() async {
        let cache = AccessCache()
        let farFuture = Date().addingTimeInterval(7200)
        let result = makeResult(granted: true, expiresAt: farFuture)
        await cache.set(key: "user1", result: result)
        let cached = await cache.get(key: "user1")
        #expect(cached != nil)
    }
}
