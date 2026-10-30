import Foundation

enum PlaybackLanguageName {
    static func display(_ code: String) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed.lowercased() != "und" else { return nil }
        if let name = Locale.current.localizedString(forLanguageCode: trimmed) {
            return name.localizedCapitalized
        }
        return trimmed.uppercased()
    }
}
