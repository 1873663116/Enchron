import Foundation

enum FolderListMetadataFormatter {
    static func fileSize(
        _ sizeInBytes: Int64,
        localeIdentifier: String = Locale.autoupdatingCurrent.identifier
    ) -> String {
        byteCountFormatter(localeIdentifier: localeIdentifier).string(fromByteCount: sizeInBytes)
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
        "\(fileSize(sizeInBytes, localeIdentifier: locale.identifier)) • \(modifiedDate(modifiedAt, locale: locale, timeZone: timeZone))"
    }

    static func byteCountFormatter(
        localeIdentifier: String = Locale.autoupdatingCurrent.identifier
    ) -> ByteCountFormatter {
        let cacheKey = "FileBrowsing.FolderListMetadataFormatter.byteCount.\(localeIdentifier)"
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

    static func dateFormatter(
        locale: Locale,
        timeZone: TimeZone,
        formatPreferenceSignature: String? = nil
    ) -> DateFormatter {
        let signature = formatPreferenceSignature ?? computedFormatPreferenceSignature(for: locale)
        let cacheKey = "FileBrowsing.FolderListMetadataFormatter.date.\(locale.identifier).\(timeZone.identifier).\(signature)"
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

    static func computedFormatPreferenceSignature(for locale: Locale) -> String {
        let calendarIdentifier = locale.calendar.identifier
        let dateTimeFormat = DateFormatter.dateFormat(
            fromTemplate: "yMMMdj",
            options: 0,
            locale: locale
        ) ?? "default"
        return "\(calendarIdentifier).\(dateTimeFormat)"
    }
}
