# 翻译术语表

翻译 `Localizable.xcstrings` 时必须遵守本文。含义取 `docs/CONTEXT.md`，那里是这些词的权威定义。表中给出的译法是约束，不是建议——同一概念在不同界面必须用同一个词。

`docs/CONTEXT.md` 里绝大多数术语（Residency、Media Identity、Content Revision、Viewing State Authority、Docking Region 等）是内部概念，不出现在界面文案里，不需要翻译。

## 产品概念

| 英文 | 含义 | zh-Hans | zh-Hant | ja | ko | fr | de |
|---|---|---|---|---|---|---|---|
| Environment | 一个稳定观影场景的身份，如 Ocean | 环境 | 環境 | 環境 | 환경 | environnement | Umgebung |
| Environment Card | 出现在佩戴者面前、可选择环境的那张卡片 | 环境卡片 | 環境卡片 | 環境カード | 환경 카드 | carte d'environnement | Umgebungskarte |
| Media Library | Enchron 管理的虚拟媒体分类，不拥有来源媒体 | 媒体库 | 媒體庫 | メディアライブラリ | 미디어 라이브러리 | Médiathèque | Mediathek |
| Library Folder | Media Library 里由用户管理的虚拟容器，不是文件系统目录 | 媒体库文件夹 | 媒體庫檔案夾 | ライブラリフォルダ | 라이브러리 폴더 | dossier de médiathèque | Mediathek-Ordner |
| Source | 提供媒体的来源，分 File Source（本地、SMB、WebDAV）与 Emby Source | 来源 | 來源 | ソース | 소스 | source | Quelle |
| Custom Angle | 把矩形全景画面按 180°–360° 水平覆盖角解释 | 自定义角度 | 自訂角度 | カスタム角度 | 사용자 설정 각도 | angle personnalisé | Eigener Winkel |

## 播放呈现位置

`docs/CONTEXT.md` 的 Playback Presentation 取这四个值，界面里以按钮的无障碍标签出现。

| 英文 | 含义 | zh-Hans | zh-Hant | ja | ko | fr | de |
|---|---|---|---|---|---|---|---|
| Window | 画面由主窗口承载 | 窗口 | 視窗 | ウィンドウ | 윈도우 | fenêtre | Fenster |
| Portal | 画面在主窗口内以通透的面呈现 | 传送门 | 傳送門 | ポータル | 포털 | portail | Portal |
| Docked | 画面停靠在沉浸环境里 | 停靠 | 停靠 | ドック | 도킹 | ancrage | Andocken |
| Panorama | 画面铺展成全景 | 全景 | 全景 | パノラマ | 파노라마 | panorama | Panorama |

## 通用词

这类词按各语言 Apple 系统界面的既有用词译，不要另创。

| 英文 | zh-Hans | zh-Hant | ja | ko | fr | de |
|---|---|---|---|---|---|---|
| Playback | 播放 | 播放 | 再生 | 재생 | lecture | Wiedergabe |
| Video | 视频 | 影片 | ビデオ | 비디오 | vidéo | Video |
| Audio | 音频 | 音訊 | オーディオ | 오디오 | audio | Audio |
| Subtitle | 字幕 | 字幕 | 字幕 | 자막 | sous-titre | Untertitel |
| Storage | 存储 | 儲存空間 | ストレージ | 저장 공간 | stockage | Speicher |
| Cache | 缓存 | 快取 | キャッシュ | 캐시 | cache | Cache |

## 不翻译

`Emby` 是产品名，所有语言保持原样。出现它的句子（`Connect to Emby`、`No Emby titles`、`Search Emby`）只翻译句子的其余部分。

`SMB`、`WebDAV`、`FFmpeg` 是协议与库名，保持原样，且不进翻译表。

## 标点

`"Open water under a slow sky, the screen mirrored in the swell."` 这条含一对引号，各语言改用本地引号：

| 语言 | 引号 |
|---|---|
| zh-Hans | “…”，弯引号 |
| zh-Hant | 「…」 |
| ja | 「…」 |
| ko | “…”，弯引号 |
| fr | « … »，内侧加不换行空格 |
| de | „…“ |

`Address: %@\nCertificate: %@\nFingerprint: %@\nValid: %@ – %@` 里的 `–` 是连接号，保留原字符。

## 复数

`%lld items` 与 `%lld selected` 两条在法语、德语需要区分单复数，按 String Catalog 的 plural variations 写成 `one` 与 `other` 两档。中文、日文、韩文无复数变化，只写一档。

法语另有一条规则：数量为 0 或 1 时动词与名词的形式，按 Apple 法语界面惯例处理。

## 待定

`SenseZone environments` 里的 SenseZone 是内部命名，不是产品名。可能应当改写而不是翻译。在决定之前这条不要翻译。

## Русский

上表各语言的对应译法，俄语另列于此：

| 英文 | 俄语 |
|---|---|
| Environment | Среда |
| Environment Card | Карточка среды |
| Media Library | Медиатека |
| Library Folder | Папка медиатеки |
| Source | Источник |
| Custom Angle | Свой угол |
| Window | Окно |
| Portal | Портал |
| Docked | Докование |
| Panorama | Панорама |
| Playback | Воспроизведение |
| Video | Видео |
| Audio | Аудио |
| Subtitle | Субтитры |
| Storage | Хранилище |
| Cache | Кэш |

`Emby`、`SMB`、`WebDAV`、`FFmpeg` 与其他语言一样保持原样。

引号用 «…»，连接号 – 保留。按钮与菜单项用不定式或名词（Отмена、Продолжить），说明文用无人称或 вы，全篇统一。

俄语有三档以上的数词变化：`%lld items`、`%lld selected` 与 `Remove %lld selected items…` 三条要写 `one`、`few`、`many`、`other` 四档，不能只写单复数两档。
