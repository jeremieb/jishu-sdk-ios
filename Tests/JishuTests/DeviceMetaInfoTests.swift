import Testing
@testable import Jishu

@Suite("Device Meta Info")
struct DeviceMetaInfoTests {
    @Test("deviceMetaInfo returns non-empty values")
    func returnsNonEmptyValues() {
        let meta = deviceMetaInfo()
        #expect(meta.osName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        #expect(meta.osVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        #expect(meta.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }
}
