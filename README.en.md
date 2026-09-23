# Enchron

[简体中文](README.md) | English

Enchron is a media player for Apple Vision Pro. It plays videos in windows and immersive spaces, and supports local files and personal SMB, WebDAV, and Emby libraries.

## Status

Enchron is preparing for external TestFlight testing. Features, compatibility, and release plans may change.

## Features

- Play videos in a window, on a docked screen, or in an immersive environment.
- Browse local media or connect to SMB, WebDAV, and Emby servers.
- Control playback and select subtitles and audio tracks.
- Use AVFoundation for hardware-accelerated decoding and rendering. HDR10, HLG, and Dolby Vision playback depends on the device and media format.
- Use FFmpeg to read common media containers. Playback of codecs such as H.264, HEVC, and AV1 depends on the device; Apple Vision Pro (M5) supports AV1.

## Build

The project requires Xcode 27.0 and the matching visionOS SDK. `Packages/PlaybackCore` depends on `PlaybackFFmpeg.xcframework`, which is not stored in Git. Run this command from the repository root after cloning:

```sh
Scripts/provision_vendored_ffmpeg.sh
```

The script builds FFmpeg. If another checkout already has the binary, pass that checkout's path to reuse it. Build and verification tools are in `Scripts/` and `Regression/`. See [`ARCHITECTURE.md`](ARCHITECTURE.md) for module ownership, [`AGENTS.md`](AGENTS.md) for project constraints, and [`Regression/README.md`](Regression/README.md) for the test protocol.

## Privacy and network access

Enchron does not run a media service or send media files, playback history, or remote-server credentials to its developer. The app connects directly to servers that users configure. It stores remote-server credentials in the device Keychain. The full [privacy notice](PRIVACY.md) is currently in Chinese.

The app permits HTTP connections to self-hosted servers without TLS. Before it sends credentials to a public HTTP address, it warns that the credentials may travel without encryption and asks for confirmation. Use HTTPS or a private encrypted network when available.

## License and third-party software

Enchron is released under the [Apache License 2.0](LICENSE). See [`NOTICE`](NOTICE) for third-party software and licenses. The app also lists these licenses in Settings.

## Contributions

We are not accepting external contributions at this time. The repository is for source inspection, reproducible builds, and license compliance. CI, signing, and release infrastructure are not available to external contributors.
