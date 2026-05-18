# ExecPlan 007 — E1/E3/E4: Photo Library + Cache Cleanup + Network Reconnection

> Created: 2026-04-02T10:00+08:00
> Branch: MinimaxTest
> Status: IN_PROGRESS

---

## Goal

Implement the final 3 features from T4.2 to complete Phase 4: Photo Library data source (E1), cache cleanup strategy (E3), and network reconnection (E4).

---

## Unit 1: E3 — Cache Cleanup (5-day expiry)

**Effort**: Minimal — protocol + implementation already exist.

The `ProgressStoring.cleanExpiredProgress(olderThan:)` method and `SwiftDataStore` implementation are fully in place. Only the call site is missing.

**File:** `XrPlayer/XrPlayerApp.swift`
- In `init()`, after constructing `PlaybackLaunchCoordinator`, add:
```swift
Task.detached(priority: .background) {
    await SwiftDataStore().cleanExpiredProgress(olderThan: 5)
}
```

---

## Unit 2: E4 — Network Reconnection

**Effort**: Small — modify ViewModel loadFiles() + View alert.

### 2a: FileBrowsingViewModel — auto-reconnect on network error

**File:** `XrPlayer/FileBrowsing/ViewModels/FileBrowsingViewModel.swift`

Add a `private var reconnectAttempted: Bool = false` flag.

Modify `loadFiles()` remote branch (lines 205-217): on catch, check if error is network-recoverable. If so and `reconnectAttempted == false`, set flag, reconnect via `connectToDataSource(activeDataSource!)`, reset flag. Otherwise surface error normally.

Add helper:
```swift
private static func isNetworkRecoverableError(_ error: Error) -> Bool {
    if let smbError = error as? SMBError {
        switch smbError {
        case .networkFailed, .notConnected: return true
        default: return false
        }
    }
    if let webDAVError = error as? WebDAVError {
        switch webDAVError {
        case .notConnected: return true
        case .requestFailed(let code) where code >= 500: return true
        default: return false
        }
    }
    return (error as NSError).domain == NSURLErrorDomain
}
```

### 2b: FileBrowserView — Retry button in error alert

**File:** `XrPlayer/FileBrowsing/Views/FileBrowserView.swift`

In the `.alert("File Browser Error", ...)` block (lines 274-290), add a "Retry" button alongside "OK":
```swift
Button("Retry") {
    viewModel.lastErrorMessage = nil
    Task { await viewModel.loadFiles() }
}
Button("OK", role: .cancel) {
    viewModel.lastErrorMessage = nil
}
```

---

## Unit 3: E1 — Photo Library Data Source

**Effort**: Medium — new adapter file + ViewModel/View wiring.

### 3a: PhotoLibraryDataSourceAdapter

**New file:** `XrPlayer/FileBrowsing/Adapters/PhotoLibrary/PhotoLibraryDataSourceAdapter.swift`

Conforms to `DataSourceConnecting & FileProviding`. Key behavior:
- `connect(with:)` → request PHPhotoLibrary authorization (.readWrite), throw if denied
- `listContents(at:)` → PHAsset.fetchAssets(with: .video, options: ...), map to MediaFile
- `listFolders(at:)` → PHAssetCollection.fetchAssetCollections for albums, map to MediaFolder
- `resolvePlayableURL(for:)` → PHAssetResourceManager export to temp file, return URL
- `resolveURL(for:)` → same as resolvePlayableURL
- `listFiles(in:sortBy:)` → fetch from specific album, apply sort
- `ownerDataSourceID: UUID` property

Path convention: root path "/" lists all videos. Album localIdentifier as folder path.

### 3b: ViewModel wiring

**File:** `XrPlayer/FileBrowsing/ViewModels/FileBrowsingViewModel.swift`

Replace the `case .photoLibrary:` stub (lines 141-144) with:
```swift
case .photoLibrary:
    let photos = PhotoLibraryDataSourceAdapter()
    photos.ownerDataSourceID = ds.id
    adapter = photos
```

### 3c: View wiring

**File:** `XrPlayer/FileBrowsing/Views/FileBrowserView.swift`

Add in the toolbar Menu, under "Local" section:
```swift
Button("Photo Library...") {
    let ds = FileBrowsingDomain.DataSource(
        id: UUID(),
        name: "Photo Library",
        sourceType: .photoLibrary,
        connectionInfo: .init(sourceType: .photoLibrary)
    )
    Task { await viewModel.connectToDataSource(ds) }
}
```

### 3d: Info.plist

Add `NSPhotoLibraryUsageDescription` key with value "Enchron needs access to your photo library to browse and play videos."

---

## Files Modified

1. `XrPlayer/XrPlayerApp.swift` (Unit 1)
2. `XrPlayer/FileBrowsing/ViewModels/FileBrowsingViewModel.swift` (Unit 2a, 3b)
3. `XrPlayer/FileBrowsing/Views/FileBrowserView.swift` (Unit 2b, 3c)
4. `XrPlayer/FileBrowsing/Adapters/PhotoLibrary/PhotoLibraryDataSourceAdapter.swift` (Unit 3a — NEW)
5. Info.plist (Unit 3d)

## Risk

- E3: Zero risk — calling existing tested code
- E4: Low risk — one-shot retry with guard, no infinite loop
- E1: Medium risk — PhotoKit on visionOS may have edge cases. Fallback: stub gracefully if Photos framework unavailable
