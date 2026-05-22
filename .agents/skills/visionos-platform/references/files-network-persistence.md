# Files, Networking, Credentials, Persistence

Use for `FileBrowsing`, local files, PhotoKit, UTType filtering, WebDAV, SMB,
URL loading, credentials, saved data sources, preferences, progress, and
persistence stores.

## Apple Sources

### Open first

- Local network privacy technote: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy
- NSLocalNetworkUsageDescription: https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription
- NSBonjourServices: https://developer.apple.com/documentation/bundleresources/information-property-list/nsbonjourservices
- Security-scoped resource access: https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource()

### Open if

- Connecting iPadOS and visionOS apps over the local network: https://developer.apple.com/documentation/visionos/connecting-ipados-and-visionos-apps-over-the-local-network
- URL Loading System: https://developer.apple.com/documentation/foundation/url_loading_system
- URLSession: https://developer.apple.com/documentation/foundation/urlsession
- Authentication challenges: https://developer.apple.com/documentation/foundation/url_loading_system/handling_an_authentication_challenge
- Network framework: https://developer.apple.com/documentation/network
- DocumentGroup: https://developer.apple.com/documentation/swiftui/documentgroup
- PhotoKit: https://developer.apple.com/documentation/photokit
- Photos authorization: https://developer.apple.com/documentation/photokit/requesting_authorization_to_access_photos
- Uniform Type Identifiers: https://developer.apple.com/documentation/uniformtypeidentifiers
- System UTTypes: https://developer.apple.com/documentation/uniformtypeidentifiers/system-declared-uniform-type-identifiers
- SwiftData: https://developer.apple.com/documentation/swiftdata
- Keychain Services: https://developer.apple.com/documentation/security/keychain-services
- visionOS privacy: https://developer.apple.com/documentation/visionos/adopting-best-practices-for-privacy

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
