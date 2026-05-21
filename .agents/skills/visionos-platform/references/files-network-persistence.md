# Files, Networking, Credentials, Persistence

Use for `FileBrowsing`, local files, PhotoKit, UTType filtering, WebDAV, SMB,
URL loading, credentials, saved data sources, preferences, progress, and
persistence stores.

## Apple Sources

- URL Loading System: https://developer.apple.com/documentation/foundation/url_loading_system
- URLSession: https://developer.apple.com/documentation/foundation/urlsession
- Authentication challenges: https://developer.apple.com/documentation/foundation/url_loading_system/handling_an_authentication_challenge
- Network framework: https://developer.apple.com/documentation/network
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
- Use URL loading authentication-challenge docs for HTTP/WebDAV auth behavior.
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
- Do not treat PhotoKit full-library access as guaranteed.
- Do not parse file types by extension when UTType or metadata is available.
- Do not block SwiftUI interaction on synchronous network/file work.
- Do not store network credentials in UserDefaults.
- Do not use UserDefaults as a general database.
- Do not import macOS preference-window assumptions into visionOS settings.

## Enchron Checkpoints

- WebDAV code should follow Foundation URL loading behavior for auth, redirects,
  errors, cancellation, and background responsiveness.
- SMB library behavior comes from the third-party client, but credentials,
  network status, file filtering, and UI behavior still follow Apple
  Foundation/Security/privacy docs.
- Saved playback progress and saved screen positions should separate user
  preferences, transient scene restoration, and credential-like secrets.
