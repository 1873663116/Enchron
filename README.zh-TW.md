# Enchron

[简体中文](README.md) | 繁體中文 | [English](README.en.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Русский](README.ru.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

[![Verification](https://github.com/1873663116/Enchron/actions/workflows/verification.yml/badge.svg?branch=main)](https://github.com/1873663116/Enchron/actions/workflows/verification.yml) [![License: GPL-3.0](https://img.shields.io/github/license/1873663116/Enchron)](LICENSE)

Enchron 是為 Apple Vision Pro 設計的媒體播放器。應用程式可在視窗和沉浸式空間中播放影片，支援本機檔案、SMB、WebDAV 和 Emby 媒體庫。

## 狀態

Enchron 已開放 TestFlight 公開測試。請使用 Apple Vision Pro，透過下方連結加入測試。功能和相容性可能會變更。

<a href="https://testflight.apple.com/join/F1xpZq6b">
  <img src="docs/assets/testflight/testflight.svg" alt="透過 TestFlight 加入 Enchron 公開測試" width="240" />
</a>

## 功能

- 在視窗、停靠螢幕和沉浸式環境中播放影片。
- 瀏覽本機媒體庫，或連線至 SMB、WebDAV 和 Emby 伺服器。
- 控制播放、切換字幕和音軌。
- 使用 AVFoundation 進行硬體加速解碼與渲染。HDR10、HLG 和 Dolby Vision 的播放能力取決於裝置及媒體格式。
- 使用 FFmpeg 解封裝常見媒體格式。H.264、HEVC 和 AV1 等編碼格式的播放能力取決於裝置；Apple Vision Pro（M5）支援 AV1。

## 建置

本專案需要 Xcode 27.2 RC 與 visionOS SDK。複製儲存庫後，請在根目錄執行以下命令，以準備 `Packages/PlaybackCore` 所需且未納入 Git 的二進位依賴項：

```sh
Scripts/provision_vendored_ffmpeg.sh
Scripts/provision_vendored_bluray.sh
```

`Scripts/build/verify_bluray_corpus.py` 會使用獨立的 MPLS 解析器驗證藍光樣本結構。藍光專項驗收資料和模擬器驗收工具位於 `Scripts/verification/`。建置與驗證入口位於 `Scripts/` 和 `Regression/`。模組所有權請參閱 [`ARCHITECTURE.md`](ARCHITECTURE.md)，專案限制請參閱 [`AGENTS.md`](AGENTS.md)，測試流程請參閱 [`Regression/README.md`](Regression/README.md)。

## 隱私與網路

Enchron 不營運媒體服務，也不會將媒體、播放記錄或遠端憑證傳送給開發者。應用程式會直接連線至使用者設定的伺服器，並將遠端憑證儲存在裝置的 Keychain 中。詳細說明請參閱 [`PRIVACY.md`](PRIVACY.md)。

為了連線至未設定 TLS 的自架伺服器，應用程式允許未加密的 HTTP。連線至公開位址前，應用程式會提醒憑證可能以未加密方式傳送，並要求確認。您也可以使用 HTTPS 或加密的私人網路。

## 開源授權與第三方元件

Enchron 以 GNU General Public License v3.0 發布。授權全文請參閱 [`LICENSE`](LICENSE)；第三方元件及其授權請參閱 [`NOTICE`](NOTICE)。應用程式的「設定」頁面也提供相關授權資訊。

## 外部貢獻

目前不接受外部貢獻。本儲存庫供查閱原始碼、重現建置及遵循授權之用。CI、簽署和發布基礎設施不對外部貢獻者開放。
