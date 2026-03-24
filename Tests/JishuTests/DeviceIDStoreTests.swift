import Testing
import Foundation
@testable import Jishu

@Suite("DeviceIDStore")
struct DeviceIDStoreTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "test.jishu.deviceid.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return defaults
    }

    @Test("Generates a non-empty UUID string on first call")
    func generatesIDOnFirstCall() {
        let defaults = freshDefaults()
        let id = DeviceIDStore.deviceID(from: defaults)
        #expect(!id.isEmpty)
        #expect(UUID(uuidString: id) != nil)
    }

    @Test("Returns the same ID on subsequent calls")
    func returnsSameIDOnSubsequentCalls() {
        let defaults = freshDefaults()
        let first = DeviceIDStore.deviceID(from: defaults)
        let second = DeviceIDStore.deviceID(from: defaults)
        #expect(first == second)
    }

    @Test("Different UserDefaults suites produce independent IDs")
    func independentSuitesMayDiffer() {
        let id1 = DeviceIDStore.deviceID(from: freshDefaults())
        let id2 = DeviceIDStore.deviceID(from: freshDefaults())
        #expect(id1 != id2)
    }
}
