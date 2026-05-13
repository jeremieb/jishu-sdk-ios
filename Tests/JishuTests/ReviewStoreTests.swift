import Testing
import Foundation
@testable import Jishu

@Suite("ReviewStore", .serialized)
struct ReviewStoreTests {
    @Test("review state is scoped per app id")
    func reviewStateIsScopedPerAppId() async {
        let suiteName = "ReviewStoreTests.reviewStateIsScopedPerAppId"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ReviewStore(defaults: defaults)

        await store.setInstallDateIfNeeded(appId: "app_one")
        await store.incrementLaunchCount(appId: "app_one")
        await store.incrementLaunchCount(appId: "app_one")
        await store.recordPromptShown(appId: "app_one")
        await store.incrementLaunchCount(appId: "app_two")

        #expect(await store.launchCount(appId: "app_one") == 2)
        #expect(await store.promptCount(appId: "app_one") == 1)
        #expect(await store.lastPromptDate(appId: "app_one") != nil)
        #expect(await store.installDate(appId: "app_one") > 0)

        #expect(await store.launchCount(appId: "app_two") == 1)
        #expect(await store.promptCount(appId: "app_two") == 0)
        #expect(await store.lastPromptDate(appId: "app_two") == nil)
    }
}
