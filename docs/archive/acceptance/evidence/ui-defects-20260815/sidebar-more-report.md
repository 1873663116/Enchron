# Sidebar More menu fix report

## Result

The code fix is complete and the beta5 physical-device build succeeds. The device Accessibility hierarchy now exposes the More menu as its own 60 x 60 button with identifier `FileBrowsing-SourcesSidebar-sourceMore`, instead of inheriting `FileBrowsing-MainWindow-sidebar`. The hover-region checker still reports zero confirmed violations.

Wearer acceptance and the requested source-addition journeys are not complete. Both live sessions exposed the app hierarchy but reported every sampled SwiftUI control as not hittable. `activate` and an app relaunch did not restore input ownership. A coordinate injection then failed with `Received invalid scene ID (nil) from Accessibility`, so using that result as proof of a real gaze-and-pinch would be false. The final `halt` returned `gracefulStop: acknowledged`, `resultBundleWritten: true`, and `remaining: []`; no runner was left resident.

## Confirmed mechanism and fix

The old label used `GlassCircleIconLabel` at `DesignTokens.Interactive.compact`, which is 36 points and explicitly requires surrounding clearance. Because the outer sidebar had an Accessibility identifier but did not declare that its children should remain separate, the physical-device hierarchy merged the More button into the sidebar container. The pre-fix evidence under `/Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/dv76-verify-20260814/grid-snapshot.json` records a 36 x 36 More button whose identifier is `FileBrowsing-MainWindow-sidebar`.

`SourceSidebar` now uses the existing `GlassCircleIconMenu`. It keeps the visual circle at 36 points and uses the component's default 60-point target. `GlassCircleIconMenu` applies a circular interaction shape to the 60-point target, then applies `enchronHoverContentShape` with 12-point insets on every edge. The hover region therefore resolves back to the 36-point visual circle instead of filling the expanded hit target. The component also hides its visual label from Accessibility and assigns the identifier to the menu itself. The sidebar adds `.accessibilityElement(children: .contain)` so the container no longer replaces its children's identities.

The sidebar-wide `.simultaneousGesture(TapGesture())` remains. Its only action is `collapseExpandedSource()`, which changes swipe-row state and does not mutate menu presentation or source-connection state. Runtime activation could not close this candidate because the current device session had no XCUI input ownership for any app control, including the unrelated Sidebar Toggle, Manage menu, Sort menu, and Breadcrumb. A wearer still needs to confirm that More opens with a real gaze-and-pinch while this gesture remains installed.

The tradeoff is deliberate: the More control now consumes a 60-point layout target rather than the old 36-point layout box. Its glass circle remains 36 points, and the 12-point hover inset prevents the larger target from producing a larger hover highlight.

## Verification evidence

The toolchain was `/Volumes/Cortisol/Applications/Xcode-beta5.app/Contents/Developer`, reporting Xcode 27.0 build `27A5237l`. The physical-device `build-for-testing` used destination `REDACTED`, test plan `InteractiveDeviceSession`, and isolated DerivedData at `/Volumes/Cortisol/DevSpace/Xcode/Enchron/DerivedData-sidebar-more-menu`. It ended with `** TEST BUILD SUCCEEDED **`.

`Scripts/verification/check_hover_region_clipping.py` produced:

```text
Scanned 65 production Swift files and 89 Button/Menu controls.
Confirmed violations: 0
Human-review candidates: 2
  Modules/DesignSystem/Components/SettingsComponents.swift:1383: Button: visual hover declaration precedes layout growth that the high-confidence size rules cannot classify
  Modules/MediaLibrary/Views/BreadcrumbView.swift:24: Button: hover effect precedes a larger layout, but the source does not declare a visual hover content shape
```

Those two human-review candidates existed outside this change and are not confirmed violations.

The first live session reached `stage: ready` with session `4DEF3963-30B6-4E69-9191-F3437F6F8335`. Its More observation was:

```text
type=Button
identifier=FileBrowsing-SourcesSidebar-sourceMore
label=More source actions
frame={{144.0, 20.0}, {60.0, 60.0}}
enabled=true
hittable=false
```

The hierarchy placed that button beneath a separate `FileBrowsing-MainWindow-sidebar` container. This proves the identifier separation and enlarged target geometry. It does not prove wearer-visible hover pixels or activation.

The coordinate attempt failed three times with `Received invalid scene ID (nil) from Accessibility` and ended the first runner. A second session, `B395212C-DFD8-46D4-9774-9289832E064D`, reached `stage: ready`. More, Sidebar Toggle, Manage, Sort, and Breadcrumb all remained not hittable after `activate` and relaunch, which isolates the current input failure from the More implementation. A current screenshot showing the built UI and the visible More circle is `/Volumes/Cortisol/DevSpace/Xcode/Enchron/TestEvidence/sidebar-more-menu-20260815/retry/7cd0cb92-45cc-4069-b485-bf1b5c5614a0.png`. It contains no gaze state and is not hover proof.

`git diff --check` passed. `Scripts/verification/controller_timings.json` was restored after the controller runs. The requested `prior-attempt.patch` was deleted.

## WebDAV

The Mac-side prerequisite is live. An authenticated depth-one PROPFIND to `http://192.168.5.2:5244/dav/` returned HTTP 207 with four DAV response elements. No credential value was written to this report or the worktree.

The device hierarchy and screenshot show a persisted `WebDAV - 192.168.5.2` source and a `Samples` folder in the current library. That state predates this run, so it is not evidence that the fixed More button added a source.

The requested end-to-end result remains open at all three product checkpoints: a new WebDAV connection was not completed through More, directory browsing was not completed from that new connection, and a remote file was not played from that new connection. The blocker was the device session's missing input ownership, not a WebDAV server failure.

## SMB

The service was retested before device work. `smbutil view` against `192.168.5.2` returned status 77 with `Authentication error`; `TestMedia` could not be enumerated. Per the task boundary, no macOS sharing setting was changed. SMB therefore stops at the server-authentication boundary. The Add SMB form was also not reached because the same device input failure prevented opening More.

## Wearer actions still required

One wearer session must close the remaining evidence gap. On the installed beta5 build, look at More and confirm that the highlight stays on the 36-point visual circle rather than filling the 60-point target, then pinch More and confirm that the Add, Refresh, and Delete menu opens. This real activation is the runtime check for the retained sidebar simultaneous gesture.

From that menu, add WebDAV with the existing `.env` values and `http://192.168.5.2:5244/dav/`, browse into `夸克`, choose a video, and start playback. During those actions the controller should capture the connection panel outcome, the new source row, the folder and video identifiers, `PlayerUI-window-control-plane`, and current-renderer pixel screenshots. Connection, browsing, and playback must be recorded as separate checkpoints.

Do not attempt SMB end to end until `smbutil view` can enumerate `TestMedia`. After the owner enables SMB access for the account and re-enters its password in macOS File Sharing options, repeat More > Add > SMB, connect to `192.168.5.2`, select `TestMedia`, browse to a video, and play it. If server authentication still fails, record the product error and stop there.
