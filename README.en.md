# Enchron

[简体中文](README.md) | English | [日本語](README.ja.md) | [한국어](README.ko.md) | [Русский](README.ru.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

[![Verification](https://github.com/1873663116/Enchron/actions/workflows/verification.yml/badge.svg?branch=main)](https://github.com/1873663116/Enchron/actions/workflows/verification.yml) [![License: GPL-3.0](https://img.shields.io/github/license/1873663116/Enchron)](LICENSE)

Enchron is a media player for Apple Vision Pro. It plays videos in windows and immersive spaces, and supports local files and SMB, WebDAV, and Emby libraries.

## Status

Enchron is available for public beta testing on TestFlight. Join on Apple Vision Pro using the link below. Features and compatibility may change.

<a href="https://testflight.apple.com/join/F1xpZq6b">
  <img src="docs/assets/testflight/testflight.svg" alt="Join the Enchron public beta on TestFlight" width="240" />
</a>

## Features

- Play videos in a window, on a docked screen, or in an immersive environment.
- Browse local media or connect to SMB, WebDAV, and Emby servers.
- Control playback and select subtitles and audio tracks.
- Use AVFoundation for hardware-accelerated decoding and rendering. HDR10, HLG, and Dolby Vision playback depends on the device and media format.
- Use FFmpeg to read common media containers. Playback of codecs such as H.264, HEVC, and AV1 depends on the device; Apple Vision Pro (M5) supports AV1.

## Build

The project requires Xcode 27.0 and the visionOS SDK. After cloning, run these commands from the repository root to provision the binary dependencies required by `Packages/PlaybackCore`. They are not stored in Git.

```sh
Scripts/provision_vendored_ffmpeg.sh
Scripts/provision_vendored_bluray.sh
```

The Blu-ray sample structure is checked against an independent MPLS parser by `Scripts/build/verify_bluray_corpus.py`. Blu-ray-specific acceptance data and simulator verification tools are in `Scripts/verification/`. Build and verification entry points are in `Scripts/` and `Regression/`. See [`ARCHITECTURE.md`](ARCHITECTURE.md) for module ownership, [`AGENTS.md`](AGENTS.md) for project constraints, and [`Regression/README.md`](Regression/README.md) for the test protocol.

## Privacy and network access

Enchron does not run a media service or send media files, playback history, or remote-server credentials to its developer. The app connects directly to servers configured by users. It stores remote credentials in the device Keychain. See [`PRIVACY.md`](PRIVACY.md) for details.

The app permits plain HTTP connections to self-hosted servers without TLS. Before connecting to a public address, it warns that credentials may be sent without encryption and asks for confirmation. HTTPS or a private encrypted network can be used instead.

## License and third-party software

Enchron is released under the GNU General Public License v3.0. See [`LICENSE`](LICENSE) for the license text and [`NOTICE`](NOTICE) for third-party software and licenses. The app also provides the relevant license information in Settings.

## External contributions

External contributions are not currently accepted. This repository is for source inspection, reproducible builds, and license compliance. CI, signing, and release infrastructure are not open to external contributors.
