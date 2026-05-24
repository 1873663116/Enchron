import Foundation

public nonisolated protocol SavedDataSourceRecordStoring: Sendable {
    func loadSavedDataSourceRecords() -> Data?
    func saveSavedDataSourceRecords(_ data: Data?)
}
