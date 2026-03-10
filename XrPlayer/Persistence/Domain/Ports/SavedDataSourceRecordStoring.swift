import Foundation

public protocol SavedDataSourceRecordStoring {
    func loadSavedDataSourceRecords() -> Data?
    func saveSavedDataSourceRecords(_ data: Data?)
}
