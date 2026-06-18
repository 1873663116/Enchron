import Foundation

/// The local file source the browsing view-model depends on: a `FileProviding`
/// + `DataSourceConnecting` adapter that also exposes a settable owning data
/// source identifier.
///
/// Both the production `LocalDataSourceAdapter` and the `FakeFileDataSource`
/// conform, so `FileBrowsingViewModel` can be driven by either without knowing
/// the concrete type. Class-bound so the view-model can hold it in a `let` and
/// still assign `ownerDataSourceID`.
public nonisolated protocol LocalFileSource: AnyObject, FileProviding, DataSourceConnecting {
    var ownerDataSourceID: UUID { get set }
}
