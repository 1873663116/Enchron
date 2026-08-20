# WebDAV 自签名证书信任询问：触发者与触发条件

调查日期 2026-08-20。工具链：`xcode-select -p` 指向 `/Volumes/Cortisol/Applications/Xcode-beta5.app/Contents/Developer`，`xcodebuild -version` 报告 Xcode 27.0（Build 27A5237l）。Apple 语义取自 Executor 的 `apple_developer_docs`，仓库事实取自当前工作树。本文不改动任何产品代码。

## 结论

**证书信任询问由 Enchron 自己触发并自己绘制，系统不参与。** 在基于 `URLSession` 的路径上，Apple 平台不提供任何服务器证书信任询问界面：系统默认行为是让连接失败。Enchron 之所以会出现询问，是因为产品实现了 `URLSessionDelegate` 的服务器信任挑战处理，并在其中调用了自绘的 SwiftUI alert。Safari 与 `WKWebView` 的证书询问由 WebKit 自身提供，与 `URLSession` 不是同一条路径，不能外推。

**自签名 HTTPS 服务器不是"连不上"，而是"连接前会问一次"。** 产品已存在完整的信任选择路径：询问 → 用户确认 → 以 `URLCredential(trust:)` 放行 → 指纹写入 `UserDefaults` → 后续（含播放阶段）静默复用。

**该询问是条件性的，四个条件必须同时成立**，缺一即不弹窗：

| 条件 | 不成立时的行为 |
|---|---|
| 请求实际走 HTTPS（地址显式带 `https://`，或端口为 443） | 走 HTTP，没有 TLS，不存在信任挑战 |
| 系统默认信任评估失败 | 评估通过则交回系统默认处理，静默连接 |
| `UserDefaults` 中该 `host:port` 未记住同一指纹 | 直接以已记忆的信任放行，不询问 |
| 当前处于"连接阶段"作用域内 | 直接取消挑战（播放阶段永不询问，符合既定产品规格） |

**在证书之前还有一道系统关卡：本地网络隐私（Local Network Privacy）。** 它是真正的系统界面，首次向局域网地址发起 TCP 连接时由系统弹出，且在用户尚未回答之前该次连接可能已被拒绝。它与证书询问是两件独立的事，回归步骤必须分开判读，不能混为一步。

**App Transport Security（ATS）不在证书之前拦截，但它规定了"委托能否放松信任"的边界。** 地址形态确实改变判定：裸私有 IP、`.local` 名、非限定主机名受 Enchron 已声明的 `NSAllowsLocalNetworking` 覆盖；而解析到私网地址的完全限定域名（FQDN，如 `nas.example.com`）不在该键覆盖范围内，ATS 完整生效。ATS 是否会使自签名证书即便经用户确认也无法放行，见下文"未能确认"一节。

**自动化可以点到确认按钮，但存在一个未验证的呈现风险。** 询问的两个按钮没有 accessibility identifier，但有可用的 label，而交互控制器支持按 label 匹配。真正的风险不在按钮，而在 alert 与连接表单 sheet 的呈现层级关系。

---

## 证据（一）：Apple 平台语义

来源均为 Apple Developer Documentation，经 `apple_developer_docs` 于 2026-08-20 取回。

### URLSession 对不受信任的服务器证书的默认行为

《Performing manual server trust authentication》（`/documentation/foundation/performing-manual-server-trust-authentication`）：

- 使用 `https` 时，`URLSessionDelegate` 会收到认证方法为 `NSURLAuthenticationMethodServerTrust` 的挑战，这是应用验证服务器身份的机会。
- 原文："In most cases, you should let the URL Loading System's default handling evaluate the server trust. You get this behavior when you either don't have a delegate or don't handle authentication challenges." 该文档随后把"连接到使用自签名证书的开发服务器"列为需要自行评估的典型场景，理由是它"would ordinarily not match anything in the system's trust store"。
- 应用要接受这样的证书，必须实现 `urlSession(_:didReceive:completionHandler:)`，并以 `URLSession.AuthChallengeDisposition.useCredential` 加 `URLCredential(trust:)` 回调；拒绝则用 `cancelAuthenticationChallenge`。
- 文档给出的示例代码在拒绝分支处写着注释 `// Show a UI here warning the user the server credentials are invalid, and cancel the load.`——**界面由应用负责，文档全篇没有描述任何系统提供的信任询问界面。**

《Handling an authentication challenge》（`/documentation/foundation/handling-an-authentication-challenge`）补充：TLS 验证属于会话级挑战，由 `URLSessionDelegate` 处理；一旦处理成功，该结果对同一 `URLSession` 创建的所有任务生效。

`urlSession(_:didReceive:completionHandler:)`（`/documentation/foundation/urlsessiondelegate/urlsession(_:didreceive:completionhandler:)`）标注 visionOS 1.0+ 可用，并说明它在"会话首次与使用 SSL 或 TLS 的远端建立连接时"被调用。

默认失败的表现形式：`URLError.serverCertificateUntrusted`（`/documentation/foundation/urlerror/servercertificateuntrusted`，"A server certificate was signed by a root server that isn't trusted"），对应 `NSURLErrorDomain` 的 -1202。《Identifying the Source of Blocked Connections》给出的 `nscurl` 样例输出即以 `Error Domain=NSURLErrorDomain Code=-1202` 呈现这一失败。

### ATS 的角色

《Preventing Insecure Network Connections》（`/documentation/security/preventing-insecure-network-connections`）：

- 默认服务器信任评估（default server trust evaluation）检查签名完整性、有效期、名称与 DNS 名匹配、以及证书链回溯到系统或用户安装的受信任锚点 CA。ATS 在此之上追加扩展检查：RSA ≥ 2048 位或 ECC ≥ 256 位、SHA-256 以上摘要、TLS 1.2 以上、AES-128/AES-256、经 ECDHE 的前向保密。
- 原文注记："When ATS is enabled, you can no longer loosen trust evaluation requirements that way, but you can still tighten them."

《Identifying the Source of Blocked Connections》（`/documentation/security/identifying-the-source-of-blocked-connections`）说明了两者的先后：证书名称不匹配之类的问题"fails default server trust evaluation **before ATS has a chance to impose its extended security checks**"。即：证书链的信任判定发生在 ATS 扩展检查之前，而信任挑战正是在该判定失败时交给委托的。

`NSAllowsLocalNetworking`（`/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking`，visionOS 1.0+）：该键"controls whether App Transport Security (ATS) allows your app to connect to unqualified domains, `.local` domains, and IP addresses using IPv4 or IPv6"。关键版本事实：**iOS 17、iPadOS 17 与 macOS 14 起，ATS 默认不再允许连接到 IP 地址**，需要 `NSAllowsLocalNetworking` 或 `NSExceptionDomains` 中的逐条 IP/CIDR 例外。该键覆盖的地址只有三类：非限定域名、`.local` 域名、IP 地址。

### 本地网络隐私

TN3179《Understanding local network privacy》（`/documentation/technotes/tn3179-understanding-local-network-privacy`）：

- "The first time a program accesses the local network, the system displays an alert asking the user to approve that access. The system records their decision, so future accesses don't prompt." 权限三态：Undetermined / Allowed / Denied，用户可在"设置 → 隐私与安全性 → 本地网络"更改。
- 平台支持表明确列出 **visionOS：支持，自 visionOS 1 起**；且"Local network privacy works the same on iOS, iPadOS, and visionOS"。
- 局域网的定义："A local network is an IP network associated with a broadcast-capable network interface"，包括 Wi-Fi 与以太网，不含蜂窝与 VPN。操作分类表中，**"Making an outgoing TCP connection"到局域网地址需要本地网络权限**。该检查实现在网络栈深处，适用于所有网络 API，明确包含 URL Loading System。
- 解析以 `.local` 结尾的名称同样需要本地网络权限；解析非本地 DNS 名不需要。
- 重要时序事实："If the system presents a local network alert in response to one of your local network operations, it may deny the operation immediately, before the user has responded to the alert." 文档建议使用 `waitsForConnectivity` 或自行重试。
- 模拟器不支持本地网络隐私，必须在真机验证。
- `NSLocalNetworkUsageDescription`（visionOS 1.0+）适用于"direct unicast or multicast connections to local hosts"，Enchron 已声明（`Config/Enchron-Info.plist:66`）。

---

## 证据（二）：Enchron 当前实现

### 触发链

1. **统一的会话与委托**。`Modules/MediaSource/ServerTrustPolicy.swift:192-203` 定义 `MediaSourceNetwork.shared`，其 `session` 是以 `ServerTrustPolicy.shared` 为 delegate 构造的 `URLSession`。WebDAV 适配器默认使用它（`Modules/MediaLibrary/Sources/WebDAV/WebDAVDataSourceAdapter.swift:44-47`），Emby 客户端与 Artwork 网络同样使用它（`Modules/Emby/EmbyClient.swift:22`、`Apps/Enchron/EnchronApplication.swift:141`）。所有网络请求共用一处证书判断，符合 ADR 0020 与 03 计划的 S1 条目。

2. **委托实现**。`ServerTrustPolicy.urlSession(_:didReceive:completionHandler:)`（同文件 `:49-96`）的判定顺序：
   - 非服务器信任挑战、或取不到 `serverTrust`/证书链首证书 → `.performDefaultHandling`（`:54-59`）。
   - `SecTrustEvaluateWithError(trust, nil)` 为真（系统评估已通过）→ `.performDefaultHandling`（`:60-63`）。
   - 计算 `host:port` 键与证书 SHA-256 指纹；若 `UserDefaults` 已记住相同指纹 → 直接 `.useCredential`，不询问（`:65-73`）。
   - 若当前不在连接批准作用域内，或未安装 `approvalHandler` → `.cancelAuthenticationChallenge`，不询问（`:74-78`）。
   - 否则组装 `ServerCertificateInfo`（地址、证书名、指纹、有效期）并在主线程调用 `approvalHandler`；用户同意则记忆指纹并 `.useCredential`，否则取消（`:80-95`）。

3. **"连接阶段"的界定**。`withConnectionApproval(to:operation:)`（`:33-47`）以 `host:port` 为键做引用计数，只在其作用域内允许询问。WebDAV 仅在 `connect(with:)` 中包裹（`WebDAVDataSourceAdapter.swift:55-59`），Emby 仅在其连接入口包裹（`EmbyClient.swift:46`）。播放期的字节读取由 `WebDAVByteRangeSource` 走同一 session（`WebDAVDataSourceAdapter.swift:176-181`、`:442-463`）但不在该作用域内，因此播放阶段遇到未记忆的证书只会取消挑战，不会弹窗。

4. **询问界面是产品自绘**。`Apps/Enchron/EnchronApplication.swift:149-152` 在应用初始化时把 `ServerTrustPolicy.shared.approvalHandler` 接到 `CertificateTrustPrompt`；`Apps/Enchron/CertificateTrustPrompt.swift` 是一个 `@Observable` 的串行请求队列，用 `CheckedContinuation` 挂起等待用户答复；`Apps/Enchron/MainView.swift:273-290` 是唯一的呈现处：

   - SwiftUI `.alert`，标题 `"无法验证服务器证书"`；
   - 按钮 `"信任"`（`role: .destructive`，`:280`）与 `"取消"`（`role: .cancel`，`:283`）；
   - message 由 `certificateDescription`（`:293-299`）拼出地址、证书名、指纹、有效期四项，满足 03 计划的 S2 条目。

   **这是应用进程内的 SwiftUI alert，不是系统界面。** 全仓库没有第二处证书询问实现。

5. **指纹记忆**。键为 `server-certificate-fingerprint.<host:port>`（`ServerTrustPolicy.swift:187-189`），写入 `UserDefaults.standard`（默认初始化，`:29-31`）。全仓库只有 `ServerTrustPolicy` 读写该键；**产品没有任何"忘记此证书"的入口**。指纹格式为大写十六进制、冒号分隔（`:98-102`），与 `openssl x509 -fingerprint -sha256` 的输出格式一致，可直接对照。

### 地址形态如何决定是否走 HTTPS

`FileBrowsingDomain.ConnectionInfo.remote`（`Modules/MediaLibrary/Model/MediaSource.swift:100-147`）先经 `canonicalAddress`（`:217-230`）：**若用户输入不含 `://`，WebDAV 一律补成 `http://`**。随后 `WebDAVDataSourceAdapter.buildBaseURL`（`:269-286`）在 `info.scheme` 为空时回退为 `info.port == 443 ? "https" : "http"`。

结论：要让请求真正走 HTTPS，用户必须在地址栏显式输入 `https://…`，或使用 443 端口。输入 `192.168.1.10:5006` 会得到 HTTP 请求，永远不会出现证书询问。

`ServerTrustPolicy` 的地址键在两侧都用 `host.lowercased()` 与"缺省端口按 scheme 推断"（`:175-185`），与挑战 `protectionSpace` 的 `host`/`port` 一致，未发现键不匹配的路径。

### 应用侧配置

`Config/Enchron-Info.plist:61-67`：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
<key>NSLocalNetworkUsageDescription</key>
<string>Enchron connects to media servers on your local network to browse and stream videos.</string>
```

没有 `NSAllowsArbitraryLoads`，没有 `NSExceptionDomains`，没有 `NSBonjourServices`（产品按地址直连，不做 Bonjour 浏览，因此不需要）。

### 自动化可达性

- 连接表单是 `FilesScreen` 的 `.sheet`（`Apps/Enchron/Screens/FilesScreen.swift:236-249`），identifier 前缀 `FileBrowsing-SourceConnection-webDAV-`。
- 证书 alert 的两个按钮**没有** `accessibilityIdentifier`（`MainView.swift:280`、`:283`），但 label 为 `信任` / `取消`。
- 交互控制器的元素解析（`Tests/EnchronAppUI/Interactive/InteractiveDeviceUITests.swift:285-302`）在 `app.descendants(matching: .any)` 上支持两种匹配：`identifier` 与 `NSPredicate(format: "label == %@")`。SwiftUI alert 在应用进程内呈现，属于 `app` 元素树。
- 因此 `tap --label 信任` 在结构上应当可以命中。`.agents/skills/visionpro-xcuitest/features/remote-source-connection.md:61` 写的"没有 accessibility identifier，合成驱动无法命中"只对 `--identifier` 成立，**对 `--label` 是过度断言**；该行应在真机确认后更正。
- 本地网络系统弹窗由 `addUIInterruptionMonitor` 覆盖，其接受的按钮 label 为 `Allow` / `允许`（`InteractiveDeviceUITests.swift:12-23`）。

### 测试覆盖

`ServerTrustPolicy` 与 `CertificateTrustPrompt` 在 `Tests/` 下没有任何引用（仅 `Apps/` 与 `Modules/` 中的定义与接线处出现）。这条路径当前**完全没有自动化测试看守**，无论模拟器单测还是设备回归。

---

## 未能确认

以下四项无法由文档或静态代码判定，需要实测。

1. **ATS 是否允许委托为局域网地址放行自签名证书。** 文档确证的是两句话："不能为受 ATS 保护的域放松服务器信任要求"，以及"`NSAllowsLocalNetworking` 控制 ATS 是否允许连接到非限定域名、`.local` 域名和 IP 地址"。两句话之间的关系——即该键是否使这三类地址不再"受 ATS 保护"从而允许放松信任——在可取回的文档中没有明确表述。判别办法：在 Mac 上对目标服务器执行 `/usr/bin/nscurl --ats-diagnostics --verbose https://<server>`，观察"ATS Default Connection"与各例外组合的通过情况；以及在真机上跑一次完整流程，看点击"信任"之后请求是成功还是仍以 -1202 结束。此项直接决定第 4 步的判据写法。

2. **alert 能否在 sheet 存在时呈现。** 证书 alert 挂在 `MainView.platformContent`（`MainView.swift:273`），而连接表单是其后代 `FilesScreen` 呈现的 `.sheet`（`FilesScreen.swift:236`）；连接过程中 sheet 仍未关闭（`onConnected: dismissSourceConnection` 只在成功后关闭）。祖先视图在已有 modal 呈现时能否叠加呈现 alert，SwiftUI 未作承诺，静态代码无法判定。若不能呈现，`CertificateTrustPrompt` 的 continuation 永不 resume，连接将无限期挂起而非报错——这是本条路径风险最高的未知项，应作为第一个真机观察点。

3. **取消挑战后连接失败的具体错误分类。** `cancelAuthenticationChallenge` 之后 `URLSession` 返回的错误未在代码中被专门映射，`connect` 只是把 `error.localizedDescription` 写入 `connectionStatus`（`WebDAVDataSourceAdapter.swift:65-68`）。03 计划 E2 要求"连接来源失败分四类：凭据、证书、找不到服务器、地址格式"，证书一类当前是否能与其他三类区分，需要在设备上取实际文案后判定。

4. **`.local` 名称的完整链路。** 代码路径对 `.local` 与裸 IP 没有差异，但 `.local` 解析额外需要本地网络权限（TN3179），且证书的 SAN 必须覆盖该名称才不会引入名称不匹配这一额外失败因子。未在设备上验证过。

---

## 设备回归的前置条件与步骤设计

### 服务器侧

- 监听 HTTPS，证书为自签名，或由一个**未安装到设备**的私有 CA 签发。若该 CA 或该证书已被装入设备并信任，系统评估通过，`ServerTrustPolicy` 走 `.performDefaultHandling`，不会弹窗。
- 证书本身应满足 ATS 的扩展要求（TLS 1.2 以上、RSA ≥ 2048 或 ECC ≥ 256、SHA-256 以上签名、支持 ECDHE、AES）。这样一旦确认信任后仍然失败，可以判定原因是 ATS 的信任放松限制，而不是服务器基础配置。
- 证书的 SAN 必须覆盖将要输入的地址形态（IP 地址需要 IP SAN），避免"名称不匹配"与"锚点不受信任"两种失败混在一起。
- 汇总片源 `sdr-bframe-aggregate-30s.mkv` 与其外挂边车置于固定目录。旅程开始前主机侧探活：`curl -k -u <user>:<pass> -X PROPFIND` 根目录成功、文件在位。
- 主机侧取一次期望指纹备用：`openssl s_client -connect <host>:<port> </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256`。

### 地址形态

- 使用**裸私有 IP** 或 **`.local` 名**（受 `NSAllowsLocalNetworking` 覆盖的三类地址之一）。不要使用解析到私网的 FQDN——该形态不被该键覆盖，ATS 完整生效，会引入第 1 项未确认因素之外的额外变量。
- 地址栏输入必须显式带 `https://` 前缀，或使用 443 端口。否则请求走 HTTP，本步骤直接失去意义。

### 应用侧状态

- 目标 `host:port` 在 `UserDefaults` 中没有已记忆指纹。由于产品没有"忘记此证书"入口，**重复触发只有三条路**：卸载重装应用、抹机、或轮换服务器证书使指纹变化（后者同时覆盖 03 计划 S3 条目）。旅程若要可重复运行，应把"卸载重装"写进 P0 前置，或固定采用轮换证书的方式。
- 本地网络权限必须先行处理，且**与证书询问分两步判读**：
  1. 应用首次向该局域网地址发起连接时，系统弹出本地网络询问。该弹窗属系统域，按在应用内可达性承诺豁免，由 `addUIInterruptionMonitor` 的 `Allow`/`允许` 分支处理。
  2. TN3179 明示该次操作可能在用户回答之前即被拒绝，因此**第一次 connect 很可能直接失败**。判据应写成"授予本地网络权限后重试一次 connect"，而不是"第一次 connect 必须成功"。
- 应用必须在前台（TN3179：后台执行局域网操作时系统直接拒绝且不弹窗、不记录决定）。
- 模拟器不支持本地网络隐私，本步骤只在真机成立。

### 步骤与判据

1. **本地网络权限**：填入地址与凭据 → tap connect → 系统弹窗出现 → 中断监视器点"允许" → 记录权限已授予。判据：权限弹窗出现且被接受；本步不对连接结果下结论。
2. **证书信任询问**：重试 connect → 出现标题为"无法验证服务器证书"的 alert。判据：
   - alert 出现（若不出现且连接挂起不返回，即命中第 2 项未确认风险，按缺陷记录）；
   - message 中的指纹与主机侧 `openssl` 取到的指纹逐字符相等（机械判据）；
   - `tap --label 信任` 能命中并生效（若只能按 identifier 命中失败，按在应用内可达性承诺记可访问性缺陷，不豁免）。
3. **确认后的连接结果**：判据为连接继续并列出根目录。若确认后仍以证书错误结束，即第 1 项未确认（ATS 禁止放松信任）成立，按内容条件缺口记录并同时形成一条产品结论：局域网自签名 HTTPS 在当前 ATS 配置下不可达，需要改用 `NSExceptionDomains` 逐条例外或改由用户安装 CA 描述文件。
4. **播放阶段不再询问**：从该来源打开汇总片源。判据：播放期间不出现证书 alert，且播放正常起播——这同时证明第 3 步已把指纹写入记忆，且 `withConnectionApproval` 的作用域界定生效。
5. （可选，覆盖 03 计划 S3）**证书轮换**：更换服务器证书后重新连接，判据为再次出现询问且指纹与新证书一致。

### 与现有旅程集的关系

`docs/plans/04-regression-journeys/draft.md:179` 的 J02 步骤 4 目前把证书信任询问写成一步。据本文结论，它至少要拆成"本地网络权限"与"证书信任询问"两步，且需要补上"必须带 `https://` 前缀"与"卸载重装以清除记忆指纹"两项前置条件。`draft.md:309` 中"无 identifier 即可访问性缺陷"的裁决维持不变，但判据应改为"按 identifier 命中失败、按 label 命中成功"这一具体形态。
