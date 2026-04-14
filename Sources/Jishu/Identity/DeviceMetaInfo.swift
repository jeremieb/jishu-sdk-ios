import Foundation
import Darwin

func deviceMetaInfo() -> (osName: String, osVersion: String, deviceName: String) {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    #if canImport(UIKit)
    let osName = "iOS"
    #else
    let osName = "macOS"
    #endif
    let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

    let identifier = hardwareIdentifier()
    return (
        osName: osName.isEmpty ? "iOS" : osName,
        osVersion: osVersion,
        deviceName: identifier.isEmpty ? "unknown" : identifier
    )
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
