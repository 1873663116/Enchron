# Enchron

[简体中文](README.md) | [繁體中文](README.zh-TW.md) | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Русский](README.ru.md) | [Français](README.fr.md) | Deutsch

[![Verification](https://github.com/1873663116/Enchron/actions/workflows/verification.yml/badge.svg?branch=main)](https://github.com/1873663116/Enchron/actions/workflows/verification.yml) [![License: GPL-3.0](https://img.shields.io/github/license/1873663116/Enchron)](LICENSE)

Enchron ist ein Mediaplayer für Apple Vision Pro. Die App spielt Videos in Fenstern und immersiven Umgebungen ab und unterstützt lokale Dateien sowie SMB-, WebDAV- und Emby-Mediatheken.

## Status

Enchron ist als öffentliche Beta über TestFlight verfügbar. Nimm über den folgenden Link auf Apple Vision Pro am Test teil. Funktionen und Kompatibilität können sich ändern.

<a href="https://testflight.apple.com/join/F1xpZq6b">
  <img src="docs/assets/testflight/testflight.svg" alt="An der öffentlichen Enchron-Beta auf TestFlight teilnehmen" width="240" />
</a>

## Funktionen

- Videos in einem Fenster, auf einem angedockten Bildschirm oder in einer immersiven Umgebung abspielen.
- Lokale Medien durchsuchen oder eine Verbindung zu SMB-, WebDAV- und Emby-Servern herstellen.
- Wiedergabe steuern sowie Untertitel und Audiospuren auswählen.
- AVFoundation für hardwarebeschleunigte Dekodierung und Darstellung verwenden. Die Wiedergabe von HDR10, HLG und Dolby Vision hängt vom Gerät und Medienformat ab.
- Mit FFmpeg gängige Mediencontainer lesen. Die Unterstützung von Codecs wie H.264, HEVC und AV1 hängt vom Gerät ab; Apple Vision Pro (M5) unterstützt AV1.

## Build

Das Projekt benötigt Xcode 27.0 und das visionOS SDK. Führe nach dem Klonen im Stammverzeichnis des Repositorys die folgenden Befehle aus, um die nicht in Git gespeicherten Binärabhängigkeiten für `Packages/PlaybackCore` bereitzustellen.

```sh
Scripts/provision_vendored_ffmpeg.sh
Scripts/provision_vendored_bluray.sh
```

Die Struktur der Blu-ray-Beispiele wird mit `Scripts/build/verify_bluray_corpus.py` anhand eines unabhängigen MPLS-Parsers geprüft. Blu-ray-spezifische Prüfdaten und Simulator-Verifikationstools befinden sich in `Scripts/verification/`. Build- und Verifikationswerkzeuge liegen in `Scripts/` und `Regression/`. Informationen zur Modulzuständigkeit stehen in [`ARCHITECTURE.md`](ARCHITECTURE.md), Projektvorgaben in [`AGENTS.md`](AGENTS.md) und der Testablauf in [`Regression/README.md`](Regression/README.md).

## Datenschutz und Netzwerk

Enchron betreibt keinen Mediendienst und sendet weder Medien noch Wiedergabeverlauf oder Zugangsdaten für entfernte Server an den Entwickler. Die App verbindet sich direkt mit den von Nutzern konfigurierten Servern und speichert die Zugangsdaten im Keychain des Geräts. Weitere Informationen stehen in [`PRIVACY.md`](PRIVACY.md).

Für selbst gehostete Server ohne TLS erlaubt die App unverschlüsselte HTTP-Verbindungen. Vor einer Verbindung zu einer öffentlichen Adresse warnt sie, dass Zugangsdaten unverschlüsselt übertragen werden können, und fragt nach einer Bestätigung. Alternativ können HTTPS oder ein verschlüsseltes privates Netzwerk verwendet werden.

## Lizenz und Drittanbieter-Software

Enchron wird unter der GNU General Public License v3.0 veröffentlicht. Der Lizenztext steht in [`LICENSE`](LICENSE); Drittanbieter-Software und deren Lizenzen sind in [`NOTICE`](NOTICE) aufgeführt. Die App zeigt die entsprechenden Lizenzinformationen auch in den Einstellungen an.

## Externe Beiträge

Derzeit werden keine externen Beiträge angenommen. Dieses Repository dient der Einsicht in den Quellcode, reproduzierbaren Builds und der Einhaltung von Lizenzen. CI, Signierung und Veröffentlichungsinfrastruktur stehen externen Mitwirkenden nicht zur Verfügung.
