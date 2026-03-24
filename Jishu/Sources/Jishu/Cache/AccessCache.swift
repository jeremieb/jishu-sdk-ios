import Foundation

actor AccessCache {
    private struct Entry {
        let result: AccessResult
        let expiry: Date
    }

    private var store: [String: Entry] = [:]

    func get(key: String) -> AccessResult? {
        guard let entry = store[key] else { return nil }
        if entry.expiry > Date() {
            return entry.result
        }
        store.removeValue(forKey: key)
        return nil
    }

    func set(key: String, result: AccessResult) {
        guard result.granted else { return }
        let fiveMinutesFromNow = Date().addingTimeInterval(300)
        let expiry: Date
        if let expiresAt = result.expiresAt {
            expiry = min(expiresAt, fiveMinutesFromNow)
        } else {
            expiry = fiveMinutesFromNow
        }
        store[key] = Entry(result: result, expiry: expiry)
    }

    func clear() {
        store.removeAll()
    }
}
