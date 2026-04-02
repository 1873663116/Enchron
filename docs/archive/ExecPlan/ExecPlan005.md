# ExecPlan 005 — T4.2 Playback Behavior & UX Features (B2/B3/E2/C2/C3)

> Created: 2026-04-02T08:00+08:00
> Branch: MinimaxTest
> Status: DONE

---

## Goal

Implement 5 remaining gap items from T4.1 audit that are cohesively related to playback behavior and UX:
- **B2**: Playback end behavior setting (stop / repeat / play next)
- **B3**: Default playback speed setting
- **E2**: Auto-next-episode on playback end
- **C2**: Resume playback prompt in VideoDetailView
- **C3**: File list progress indicator

---

## Unit 1: Domain + Persistence — PlaybackEndBehavior, UserPreferences, UserDefaultsStore

### 1a. New file: `XrPlayer/Persistence/Domain/ValueObjects/PlaybackEndBehavior.swift`

```swift
import Foundation

extension PersistenceDomain {
    public enum PlaybackEndBehavior: Sendable, Hashable {
        case stop
        case repeatOne
        case playNext
    }
}
```

### 1b. Edit: `XrPlayer/Persistence/Domain/Entities/UserPreferences.swift`

Add two new fields:
```swift
public var playbackEndBehavior: PlaybackEndBehavior
public var defaultPlaybackSpeed: Double
```
Update init with defaults: `.stop` and `1.0`.

### 1c. Edit: `XrPlayer/Persistence/Adapters/UserDefaultsStore.swift`

Add keys:
```swift
private static let endBehaviorKey = "xrplayer.preferences.endBehavior"
private static let defaultSpeedKey = "xrplayer.preferences.defaultSpeed"
```

Update `loadPreferences()`:
- `endBehavior`: read string, map "stop"/"repeatOne"/"playNext", default "stop"
- `defaultSpeed`: read double, default 1.0

Update `savePreferences()`:
- Write both new values.

---

## Unit 2: Settings UI (B2 + B3)

### Edit: `XrPlayer/Settings/Views/SettingsView.swift`

Add `@State private var playbackEndBehavior: PersistenceDomain.PlaybackEndBehavior = .stop`
Add `@State private var defaultPlaybackSpeed: Double = 1.0`

In the "Playback" section, add:
- Picker for end behavior: "When Video Ends" — Stop / Repeat / Play Next
- Picker for default speed: "Default Speed" — all 10 PlaybackSpeed values, display as "0.25x" ... "5.0x"

Wire `onAppear` to load and `onChange` to save (same pattern as `resumePolicy`).

---

## Unit 3: Auto-Next Episode (E2)

### 3a. Edit: `XrPlayer/App/PlaybackLaunchCoordinator.swift`

Add dependency:
```swift
private let preferencesStore: PreferencesStoring
```

Add closure:
```swift
public var nextFileProvider: (@MainActor @Sendable () async -> PlaybackLaunchRequest?)?
```

Update init to accept `preferencesStore: PreferencesStoring = UserDefaultsStore()`.

Add method:
```swift
/// Handles playback-ended event based on user preferences.
/// Returns true if UI should show controls (playback stopped), false if auto-continuing.
public func handlePlaybackEnded() -> Bool {
    let prefs = preferencesStore.loadPreferences()
    switch prefs.playbackEndBehavior {
    case .stop:
        return true
    case .repeatOne:
        windowVideoViewModel.replay()
        return false
    case .playNext:
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let next = await self.nextFileProvider?() {
                self.beginPlayback(next)
            }
        }
        return false
    }
}
```

### 3b. Edit: `XrPlayer/MainView.swift`

Change onPlaybackEnded handler:
```swift
windowVideoViewModel.onPlaybackEnded = {
    let shouldShowControls = playbackLauncher.handlePlaybackEnded()
    if shouldShowControls {
        withAnimation { appModel.showControls = true }
        controlsTimerTask?.cancel()
    }
}
```

### 3c. Edit: `XrPlayer/XrPlayerApp.swift`

After creating launcher and fileBrowsingViewModel, wire the nextFileProvider:
```swift
launcher.nextFileProvider = { [weak fileBrowsingViewModel, weak windowVideoViewModel] in
    guard let vm = fileBrowsingViewModel,
          let currentRequest = windowVideoViewModel?.currentLaunchRequest else { return nil }
    
    guard let currentIndex = vm.files.firstIndex(where: {
        $0.name == currentRequest.displayName
    }) else { return nil }
    
    let nextIndex = currentIndex + 1
    guard nextIndex < vm.files.count else { return nil }
    
    return try? await vm.playbackRequest(for: vm.files[nextIndex])
}
```

### 3d. Apply Default Speed

In `PlaybackLaunchCoordinator.beginPlayback`, after play starts:
```swift
let defaultSpeed = preferencesStore.loadPreferences().defaultPlaybackSpeed
if defaultSpeed != 1.0 {
    windowVideoViewModel.setSpeed(PlaybackCoreDomain.PlaybackSpeed(defaultSpeed))
}
```
Same in `confirmPlayback`.

---

## Unit 4: Resume Playback Prompt (C2)

### 4a. Edit: `XrPlayer/App/PlaybackLaunchCoordinator.swift`

Add resumePosition parameter to confirmPlayback:
```swift
public func confirmPlayback(_ prepared: PreparedPlayback, resumePosition: Double? = nil) {
    // ... existing code ...
    windowVideoViewModel.resume()
    if let pos = resumePosition, pos > 0 {
        // Small delay to let mpv initialize playback before seeking
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            self?.windowVideoViewModel.seek(to: pos)
        }
    }
}
```

Expose progressStore as internal for VideoDetailView to query:
```swift
public func loadProgress(for fileID: PersistenceDomain.FileIdentifier) async -> PersistenceDomain.PlaybackProgress? {
    await progressStore.loadProgress(for: fileID)
}
```

### 4b. Edit: `XrPlayer/PlayerUI/Views/VideoDetailView.swift`

Add state:
```swift
@State private var savedProgress: PersistenceDomain.PlaybackProgress?
@State private var resumePolicy: PersistenceDomain.ResumePolicy = .askEveryTime
```

In `readyContent(prepared:)`, replace the single Play button with:
- If `savedProgress != nil && resumePolicy == .askEveryTime`:
  - Primary: "Resume from X:XX" button → confirmPlayback(prepared, resumePosition: savedProgress.position.seconds)
  - Secondary: "Play from Start" button → confirmPlayback(prepared, resumePosition: nil)
- If `savedProgress != nil && resumePolicy == .alwaysResume`:
  - Single "Play" button → auto-passes resumePosition
- Else:
  - Single "Play" button → no resumePosition

Load progress when preparation becomes `.ready`:
```swift
.onChange(of: coordinator.currentPreparation) { _, newState in
    if case .ready(let prepared) = newState,
       let fileID = prepared.request.fileIdentifier {
        Task {
            savedProgress = await coordinator.loadProgress(for: fileID)
            resumePolicy = UserDefaultsStore().loadPreferences().resumePolicy
        }
    }
}
```

Format time helper: `formatTime(_ seconds: Double) -> String` (MM:SS or H:MM:SS).

---

## Unit 5: File List Progress Indicator (C3)

### 5a. Edit: `XrPlayer/FileBrowsing/ViewModels/FileBrowsingViewModel.swift`

Add dependency:
```swift
private let progressStore: ProgressStoring
```

Add state:
```swift
public var fileProgressMap: [String: Double] = [:]  // fileID.rawValue -> seconds
```

Add non-async `makeFileIdentifierForLookup` method:
```swift
public func makeFileIdentifierForLookup(for file: FileBrowsingDomain.MediaFile) -> PersistenceDomain.FileIdentifier {
    let path: String
    let serverFingerprint: String?
    if let dataSource = activeDataSource {
        let logicalDirectory = currentRemotePath == "/" ? "" : currentRemotePath
        path = "\(logicalDirectory)/\(file.name)"
        let host = dataSource.connectionInfo.host ?? dataSource.name
        let port = dataSource.connectionInfo.port.map(String.init) ?? "-"
        serverFingerprint = "\(dataSource.sourceType.rawValue):\(host):\(port)"
    } else {
        path = file.url.path
        serverFingerprint = nil
    }
    return PersistenceDomain.FileIdentifier.make(path: path, sizeInBytes: file.sizeInBytes, serverFingerprint: serverFingerprint)
}
```

After `applySortToFiles()` in `loadFiles()`, call `loadProgressForFiles()`:
```swift
private func loadProgressForFiles() {
    Task { [weak self] in
        guard let self else { return }
        var map: [String: Double] = [:]
        for file in self.files {
            let fileID = self.makeFileIdentifierForLookup(for: file)
            if let progress = await self.progressStore.loadProgress(for: fileID) {
                map[fileID.rawValue] = progress.position.seconds
            }
        }
        self.fileProgressMap = map
    }
}
```

Update init to accept `progressStore: ProgressStoring = SwiftDataStore()`.

### 5b. Edit: `XrPlayer/FileBrowsing/Views/FolderListView.swift`

Add parameter:
```swift
public let fileProgress: [String: Double]  // fileID.rawValue -> seconds watched
```

In file row, below the size/date line, if progress exists for this file, show:
```swift
if let seconds = fileProgress[fileIdentifierForFile] {
    HStack(spacing: 4) {
        Circle()
            .fill(.orange)
            .frame(width: 6, height: 6)
        Text("Watched \(formatWatchedTime(seconds))")
            .font(.caption2)
            .foregroundStyle(.orange)
    }
}
```

BUT: FolderListView doesn't have access to file identifiers. We need to pass a lookup function or pre-compute a mapping by file ID (UUID).

Better approach: Have FileBrowsingViewModel compute a `fileWatchedSeconds: [UUID: Double]` map (keyed by MediaFile.id UUID). Then FolderListView takes `fileWatchedSeconds: [UUID: Double]`.

### 5c. Edit: `XrPlayer/FileBrowsing/Views/FileBrowserView.swift`

Pass progress data to FolderListView:
```swift
FolderListView(
    ...
    fileWatchedSeconds: viewModel.fileWatchedSeconds
)
```

### 5d. Edit: `XrPlayer/XrPlayerApp.swift`

Update FileBrowsingViewModel init to pass progressStore.

---

## Execution Record

### Unit 1: Domain + Persistence
- New file: `PlaybackEndBehavior.swift` (stop/repeatOne/playNext enum)
- `UserPreferences.swift`: +2 fields (playbackEndBehavior, defaultPlaybackSpeed)
- `UserDefaultsStore.swift`: +2 keys, updated load/save with switch statements
- `swift build` → Build complete
- `swift test` → 205 tests, 0 failures

### Unit 2: Settings UI (B2 + B3)
- `SettingsView.swift`: +2 Pickers (When Video Ends, Default Speed), +2 @State, +3 onChange handlers
- Speed label helper formats display text

### Unit 3: Auto-Next Episode (E2)
- `PlaybackLaunchCoordinator.swift`: +preferencesStore dep, +nextFileProvider closure, +handlePlaybackEnded() method
- `MainView.swift`: onPlaybackEnded → calls handlePlaybackEnded(), conditionally shows controls
- `XrPlayerApp.swift`: wires nextFileProvider (finds next file by displayName match in sorted list)
- Default speed applied in both beginPlayback and confirmPlayback paths

### Unit 4: Resume Playback Prompt (C2)
- `PlaybackLaunchCoordinator.swift`: confirmPlayback gains resumePosition:Double? parameter, +loadProgress() public method
- `VideoDetailView.swift`: @State savedProgress + resumePolicy, .task loads progress on ready, playbackButtons() renders:
  - askEveryTime + progress > 5s → "Resume from X:XX" (primary) + "Play from Start" (secondary)
  - alwaysResume → single Play button with auto-resume
  - alwaysStartFromBeginning or no progress → single Play button

### Unit 5: File List Progress Indicator (C3)
- `FileBrowsingViewModel.swift`: +progressStore dep, +fileWatchedSeconds [UUID: Double], +makeFileIdentifierForLookup() (non-async), +loadProgressForFiles() called after applySortToFiles()
- `FolderListView.swift`: +fileWatchedSeconds param, renders orange dot + "Watched X:XX" for files with progress > 5s
- `FileBrowserView.swift`: passes viewModel.fileWatchedSeconds to FolderListView

### Verification
- `swift build` → Build complete (0.93s)
- `swift test` → 205 tests, 0 failures
- REGRESSION.md: +5 new items (REG-085 through REG-089), updated code path index
