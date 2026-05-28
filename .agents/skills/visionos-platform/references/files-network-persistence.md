# Files, Networking, Credentials, Persistence

Use for `FileBrowsing`, local files, PhotoKit, UTType filtering, WebDAV, SMB,
URL loading, credentials, saved data sources, preferences, progress, and
persistence stores.

## Evidence Handles

Local DocSetQuery root: `/Users/xiongzhipeng/DocSetQuery/docs/apple`.
Prefer the local DocSetQuery pages below before web search. They are generated
from Apple API Reference `docset_version: 24703`.

### Open first

- `Apple-Data-State/bundleresources.md#documentation-bundleresources-information-property-list-nslocalnetworkusagedescription`
  — local network usage description key.
- `Apple-Data-State/bundleresources.md#documentation-bundleresources-information-property-list-nsbonjourservices`
  — Bonjour services declaration key.
- `Apple-System-Network/network.md#documentation-network`
  — Network framework root for path, transport, and discovery work.
- `Apple-Language-Foundation/uniformtypeidentifiers.md#documentation-uniformtypeidentifiers`
  — Uniform Type Identifiers framework root.
- `Apple-System-Network/security.md#documentation-security-keychain-services`
  — Keychain Services.

### Open if

- `Apple-UI-Frameworks/swiftui.md#documentation-swiftui-documentgroup`
  — system document scene support.
- `Apple-Media-Device/photos.md#documentation-photos`
  — Photos/PhotoKit framework root for user photo and video assets.
- `Apple-Media-Device/photos.md#documentation-photos-phphotolibrary`
  — `PHPhotoLibrary` access surface.
- `Apple-Language-Foundation/uniformtypeidentifiers.md#documentation-uniformtypeidentifiers-system-declared-uniform-type-identifiers`
  — system-declared UTTypes.
- `Apple-Data-State/swiftdata.md#documentation-swiftdata`
  — SwiftData persistence framework root.

### Search when DocSet lacks the article or Swift overlay page

- Xcode Documentation Search:
  `"TN3179" "local network privacy"`
  for the local-network privacy technote.
- Xcode Documentation Search:
  `"Connecting iPadOS and visionOS apps over the local network"`
  for visionOS local-network article guidance.
- Xcode Documentation Search:
  `"URL Loading System" "URLSession" "authentication challenge"`
  for Foundation URL loading and WebDAV-style HTTP auth behavior.
- Xcode Documentation Search:
  `"startAccessingSecurityScopedResource" "URL"`
  for Swift `URL` security-scoped resource access.
- Xcode Documentation Search:
  `"Requesting authorization to access photos" "PhotoKit"`
  for PhotoKit authorization flow.
- Xcode Documentation Search:
  `"Adopting best practices for privacy" "visionOS"`
  for platform privacy guidance.

### Official web fallback

- `https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy`

## Correct Decisions

- Use `URLSession` for HTTP/WebDAV-style URL loading unless a lower-level
  protocol requirement demands Network framework.
- Use Network framework for path monitoring, custom TCP/TLS/UDP/QUIC protocols,
  and transport-level diagnostics.
- SMB discovery, LAN WebDAV, arbitrary local-host connections, Bonjour
  browsing/registration, broadcast, and multicast are local-network privacy
  surfaces. Add `NSLocalNetworkUsageDescription` and, for Bonjour service
  browsing or registration, `NSBonjourServices`.
- Use URL loading authentication-challenge docs for HTTP/WebDAV auth behavior.
- Large media downloads, HLS manifests, and remote previews should be
  resumable or cancellable. Do not require the user to keep watching a loading
  surface for long-running network work.
- User-selected local files must come from system-mediated selection such as
  file importer/document picker flows. Persist access with security-scoped
  bookmarks when long-term access is needed; do not store raw paths as durable
  authority.
- Balance every successful `startAccessingSecurityScopedResource()` call with
  `stopAccessingSecurityScopedResource()`.
- Prefer UTType over extension-only string guesses when the system can provide
  structured type information.
- Photo library access is privacy-gated and can be limited; the app must work
  when only selected assets are visible.
- Credentials belong in Keychain, not UserDefaults or plain JSON.
- UserDefaults is acceptable for lightweight preferences or early local
  prototypes, but do not name a UserDefaults-backed class as though it were
  real SwiftData unless that is intentional and documented.
- Scene/window restoration is a platform feature. Do not duplicate it blindly
  in persistence state.

## iOS/macOS Conflicts

- Do not assume desktop file-system freedom. visionOS app file access is
  sandboxed and privacy-mediated.
- Do not assume SMB/WebDAV LAN access works without local-network privacy
  strings and denial handling.
- Do not assume a raw file path remains valid after a user selects a document.
- Do not treat PhotoKit full-library access as guaranteed.
- Do not parse file types by extension when UTType or metadata is available.
- Do not block SwiftUI interaction on synchronous network/file work.
- Do not assume scene backgrounding means the content is invisible or that
  long-running media/network work can continue without a product reason.
- Do not store network credentials in UserDefaults.
- Do not use UserDefaults as a general database.
- Do not import macOS preference-window assumptions into visionOS settings.

## Enchron Checkpoints

- WebDAV code should follow Foundation URL loading behavior for auth, redirects,
  errors, cancellation, and background responsiveness.
- SMB library behavior comes from the third-party client, but credentials,
  local-network permission state, Bonjour/service discovery, network status,
  file filtering, and UI behavior still follow Apple Foundation/Security/privacy
  docs.
- Local-file playback must keep a scoped-access plan separate from playback
  state, progress state, and recent-item UI.
- Saved playback progress and saved screen positions should separate user
  preferences, transient scene restoration, and credential-like secrets.
- Remote media features should state how cancellation, retry, partial content,
  authentication challenges, and scene lifecycle changes affect playback start.
