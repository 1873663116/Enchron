# 文件、网络、凭据、持久化

用于 `FileBrowsing`、本地文件、PhotoKit、UTType filtering、WebDAV、SMB、URL loading、credentials、已保存数据源、preferences、progress 和 persistence stores。

## 证据指针

Apple API 事实用官方 `DocumentationSearch`（`mcp__xcode__DocumentationSearch`，跟随当前 Xcode）查本 surface 相关 framework/概念，再用下面的判断段收窄到 Enchron 边界。

### 查询种子（DocumentationSearch / 官方 web）

- `"TN3179" "local network privacy"`
  用于 local-network privacy technote。
- `"Connecting iPadOS and visionOS apps over the local network"`
  用于 visionOS local-network 文章指导。
- `"URL Loading System" "URLSession" "authentication challenge"`
  用于 Foundation URL loading 和 WebDAV-style HTTP auth 行为。
- `"startAccessingSecurityScopedResource" "URL"`
  用于 Swift `URL` security-scoped resource access。
- `"Requesting authorization to access photos" "PhotoKit"`
  用于 PhotoKit authorization flow。
- `"Adopting best practices for privacy" "visionOS"`
  用于平台隐私指导。

### 官方 Web fallback

- `https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy`

## 正确判断

- 除非底层协议要求必须使用 Network framework，否则 HTTP/WebDAV-style URL loading 使用 `URLSession`。
- Network framework 用于 path monitoring、自定义 TCP/TLS/UDP/QUIC 协议和 transport-level diagnostics。
- SMB discovery、LAN WebDAV、任意 local-host connection、Bonjour browsing/registration、broadcast 和 multicast 都是 local-network privacy surface。添加 `NSLocalNetworkUsageDescription`；如果进行 Bonjour service browsing 或 registration，还要添加 `NSBonjourServices`。
- HTTP/WebDAV auth 行为查 URL loading authentication-challenge 文档。
- 大型媒体下载、HLS manifest 和远程 preview 应可恢复或可取消。不要要求用户为了长时间网络任务一直盯着 loading surface。
- 用户选择的本地文件必须来自系统中介的选择，例如 file importer/document picker flow。需要长期访问时，用 security-scoped bookmark 持久化访问权；不要把 raw path 当成持久权限。
- 每个成功的 `startAccessingSecurityScopedResource()` 调用，都要配对 `stopAccessingSecurityScopedResource()`。
- 当系统能提供结构化类型信息时，优先使用 UTType，而不是只靠扩展名字符串猜测。
- Photo library access 受隐私控制，并且可能是 limited；app 必须能在只看得到选中资产时工作。
- Credentials 属于 Keychain，不属于 UserDefaults 或明文 JSON。
- UserDefaults 可以用于轻量 preferences 或早期本地 prototype，但不要把 UserDefaults-backed class 命名得像真正 SwiftData，除非这是有意且已记录的选择。
- Scene/window restoration 是平台能力。不要在 persistence state 里盲目复制它。

## iOS/macOS 冲突点

- 不要假设桌面文件系统自由度。visionOS app 文件访问受沙盒和隐私中介约束。
- 不要假设 SMB/WebDAV LAN access 不需要 local-network privacy 字符串和 denial handling。
- 不要假设用户选择文档后 raw file path 仍然长期有效。
- 不要把 PhotoKit full-library access 视为保证存在。
- 当 UTType 或 metadata 可用时，不要按扩展名解析文件类型。
- 不要让同步网络/文件工作阻塞 SwiftUI 交互。
- 不要假设 scene backgrounding 意味着内容不可见，也不要假设长时间 media/network work 可在没有产品理由的情况下继续。
- 不要把网络凭据存进 UserDefaults。
- 不要把 UserDefaults 当通用数据库。
- 不要把 macOS preference-window 假设引入 visionOS settings。

## Enchron 检查点

- WebDAV 代码应遵循 Foundation URL loading 对 auth、redirect、error、cancellation 和 background responsiveness 的行为。
- SMB library 行为来自第三方 client，但 credentials、local-network permission state、Bonjour/service discovery、network status、file filtering 和 UI 行为仍然遵循 Apple Foundation/Security/privacy 文档。
- Local-file playback 必须把 scoped-access plan 与 playback state、progress state 和 recent-item UI 分开。
- 保存的 playback progress 和保存的 screen position 应区分 user preferences、transient scene restoration 和 credential-like secrets。
- Remote media 功能应说明 cancellation、retry、partial content、authentication challenge 和 scene lifecycle change 如何影响 playback start。
