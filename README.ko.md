# Enchron

[简体中文](README.md) | [English](README.en.md) | [日本語](README.ja.md) | 한국어 | [Русский](README.ru.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

[![Verification](https://github.com/1873663116/Enchron/actions/workflows/verification.yml/badge.svg?branch=main)](https://github.com/1873663116/Enchron/actions/workflows/verification.yml) [![License: GPL-3.0](https://img.shields.io/github/license/1873663116/Enchron)](LICENSE)

Enchron은 Apple Vision Pro용 미디어 플레이어입니다. 윈도우와 몰입형 공간에서 동영상을 재생하며, 로컬 파일, SMB, WebDAV 및 Emby 라이브러리를 지원합니다.

## 상태

Enchron은 TestFlight 공개 베타 테스트를 진행 중입니다. Apple Vision Pro에서 아래 링크를 통해 참여할 수 있습니다. 기능과 호환성은 변경될 수 있습니다.

<a href="https://testflight.apple.com/join/F1xpZq6b">
  <img src="docs/assets/testflight/testflight.svg" alt="TestFlight에서 Enchron 공개 베타 참여" width="240" />
</a>

## 기능

- 윈도우, 도킹 화면, 몰입형 환경에서 동영상을 재생합니다.
- 로컬 미디어를 탐색하거나 SMB, WebDAV 및 Emby 서버에 연결합니다.
- 재생을 제어하고 자막과 오디오 트랙을 선택합니다.
- AVFoundation을 사용해 하드웨어 가속 디코딩과 렌더링을 수행합니다. HDR10, HLG, Dolby Vision 재생은 기기와 미디어 형식에 따라 달라집니다.
- FFmpeg으로 일반적인 미디어 컨테이너를 읽습니다. H.264, HEVC, AV1 등의 코덱 재생은 기기에 따라 다르며 Apple Vision Pro(M5)는 AV1을 지원합니다.

## 빌드

프로젝트에는 Xcode 27.0과 visionOS SDK가 필요합니다. 클론한 뒤 저장소 루트에서 다음 명령을 실행해 `Packages/PlaybackCore`에 필요한 Git 미포함 바이너리 의존성을 준비하세요.

```sh
Scripts/provision_vendored_ffmpeg.sh
Scripts/provision_vendored_bluray.sh
```

Blu-ray 샘플 구조는 `Scripts/build/verify_bluray_corpus.py`에서 별도의 MPLS 파서 결과와 대조합니다. Blu-ray 전용 검수 자료와 시뮬레이터 검증 도구는 `Scripts/verification/`에 있습니다. 빌드와 검증 진입점은 `Scripts/` 및 `Regression/`에 있습니다. 모듈 소유권은 [`ARCHITECTURE.md`](ARCHITECTURE.md), 프로젝트 제약은 [`AGENTS.md`](AGENTS.md), 테스트 절차는 [`Regression/README.md`](Regression/README.md)를 참조하세요.

## 개인정보 보호 및 네트워크

Enchron은 미디어 서비스를 운영하지 않으며 미디어, 재생 기록 또는 원격 서버 자격 증명을 개발자에게 전송하지 않습니다. 앱은 사용자가 설정한 서버에 직접 연결하고 원격 자격 증명을 기기의 Keychain에 저장합니다. 자세한 내용은 [`PRIVACY.md`](PRIVACY.md)를 참조하세요.

TLS가 설정되지 않은 자체 호스팅 서버에 연결할 수 있도록 일반 HTTP 연결을 허용합니다. 공개 주소에 연결하기 전에 자격 증명이 암호화되지 않은 채 전송될 수 있음을 알리고 확인을 요청합니다. HTTPS 또는 암호화된 사설 네트워크를 사용할 수 있습니다.

## 라이선스 및 타사 소프트웨어

Enchron은 GNU General Public License v3.0에 따라 배포됩니다. 라이선스 전문은 [`LICENSE`](LICENSE), 타사 소프트웨어와 라이선스는 [`NOTICE`](NOTICE)를 참조하세요. 앱 설정에서도 관련 라이선스 정보를 제공합니다.

## 외부 기여

현재 외부 기여를 받지 않습니다. 이 저장소는 소스 확인, 재현 가능한 빌드, 라이선스 준수를 위해 공개되어 있습니다. CI, 서명 및 릴리스 기반 시설은 외부 기여자에게 공개되지 않습니다.
