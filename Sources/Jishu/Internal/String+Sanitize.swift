import Foundation

extension String {
    /// Returns `nil` if the string is blank after trimming whitespace, otherwise the trimmed string.
    var jishuNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Optional where Wrapped == String {
    /// Returns `nil` if the wrapped string is absent or blank after trimming.
    var jishuNilIfBlank: String? { self?.jishuNilIfBlank }
}
