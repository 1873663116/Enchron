import Foundation

enum FolderListMetadataFormatter {
    static func fileSize(_ sizeInBytes: Int64) -> String {
        byteCountFormatter.string(fromByteCount: sizeInBytes)
    }

    static func modifiedDate(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        dateFormatter(locale: locale, timeZone: timeZone).string(from: date)
    }

    static func subtitle(
        sizeInBytes: Int64,
        modifiedAt: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        "\(fileSize(sizeInBytes)) • \(modifiedDate(modifiedAt, locale: locale, timeZone: timeZone))"
    }

    private static var byteCountFormatter: ByteCountFormatter {
        let cacheKey = "FileBrowsing.FolderListMetadataFormatter.byteCount"
        let threadDictionary = Thread.current.threadDictionary
        if let formatter = threadDictionary[cacheKey] as? ByteCountFormatter {
            return formatter
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        threadDictionary[cacheKey] = formatter
        return formatter
    }

    private static func dateFormatter(locale: Locale, timeZone: TimeZone) -> DateFormatter {
        let cacheKey = "FileBrowsing.FolderListMetadataFormatter.date.\(locale.identifier).\(timeZone.identifier)"
        let threadDictionary = Thread.current.threadDictionary
        if let formatter = threadDictionary[cacheKey] as? DateFormatter {
            return formatter
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        threadDictionary[cacheKey] = formatter
        return formatter
    }
}
