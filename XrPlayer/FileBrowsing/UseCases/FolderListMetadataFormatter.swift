import Foundation

enum FolderListMetadataFormatter {
    static func fileSize(_ sizeInBytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeInBytes)
    }

    static func modifiedDate(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func subtitle(
        sizeInBytes: Int64,
        modifiedAt: Date,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        "\(fileSize(sizeInBytes)) • \(modifiedDate(modifiedAt, locale: locale, timeZone: timeZone))"
    }
}
