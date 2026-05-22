import Foundation
import Darwin

func deviceMetaInfo() -> (osName: String, osVersion: String, deviceName: String) {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    let identifier = hardwareIdentifier()
    return (
        osName: currentOSName(),
        osVersion: osVersion,
        deviceName: identifier.isEmpty ? "unknown" : identifier
    )
}

func currentPlatform() -> String {
    #if os(watchOS)
    return "watchos"
    #elseif os(visionOS)
    return "visionos"
    #elseif canImport(UIKit)
    return "ios"
    #else
    return "macos"
    #endif
}

func entitlementPlatform() -> String {
    "ios"
}

private func currentOSName() -> String {
    #if os(watchOS)
    return "watchOS"
    #elseif os(visionOS)
    return "visionOS"
    #elseif canImport(UIKit)
    return "iOS"
    #else
    return "macOS"
    #endif
}

private func hardwareIdentifier() -> String {
    var size: size_t = 0
    guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 1 else {
        return ""
    }

    var machine = [CChar](repeating: 0, count: Int(size))
    guard sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 else {
        return ""
    }

    let bytes = machine.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}
