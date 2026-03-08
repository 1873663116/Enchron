# XrPlayer 已知问题归档（已修复）

归档日期：2026-03-08

## 收口结论

- ✅ KI-006：WebDAV 连接成功但目录显示为空，已完成首轮真实可用修复并从主文档移出。

以下保留归档前的原始问题记录，供后续追溯。

---

## KI-006：WebDAV 连接成功但目录显示为空

### 范围

- 当前问题聚焦于：用户已成功连接 WebDAV 服务器，但文件浏览页看不到任何内容，或表现为“已连接 + 空白列表”。
- 本轮仅记录系统性排查结论，不包含修复方案。
- 本轮结论来自三路分析：`bug-finder`、`adversarial-agent`、`referee-agent`，并结合当前代码静态审查整理。

### 排序结论

1. 目录识别逻辑过于依赖特定 WebDAV 返回形式，这是当前最高概率根因。
2. “连接成功”判定过宽，只基于 `OPTIONS`，并不代表目录确实可列出。
3. 地址与路径规范化存在兼容性风险，尤其是 scheme、尾斜杠、编码和 collection path。
4. 自目录过滤与 `href` 解析失败存在静默清空结果的边界情况。
5. 仅显示可播放视频的过滤逻辑会放大前述问题，让“假空目录”更容易出现。
6. 错误提示与测试覆盖不足不是直接根因，但解释了为什么问题能持续存在且用户侧感知模糊。

### What / Why

#### 1. 目录识别失败会直接把真实目录内容变成空白

What：
- WebDAV 适配器只有两种方式把返回项识别为目录：
- 返回项被解析为 DAV `collection`
- 或 `href` 字面量以 `/` 结尾

Why：
- 如果服务器返回的子目录既没有被解析出 `collection`，`href` 也没有尾随 `/`，这些目录就会落入“文件”分支。
- 落入“文件”分支后，又会经过“仅保留可播放视频扩展名”的过滤。
- 结果就是：真实存在的目录项先被误判，再被过滤，最终 UI 看起来像空目录。
- 如果服务器根目录主要是子文件夹，这条路径与“连接成功但什么都没有”高度吻合。

代码证据：
- [WebDAVDataSourceAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift#L89)
- [WebDAVDataSourceAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift#L125)
- [WebDAVDataSourceAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift#L350)
- [FileFilter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Domain/ValueObjects/FileFilter.swift#L15)

#### 2. 当前“连接成功”并不等于“目录可浏览”

What：
- 连接阶段只对目标 URL 发送 `OPTIONS`。
- 只要 `OPTIONS` 返回 `2xx`，适配器就认为已经连接成功。
- 真正决定能否看到目录内容的是后续 `PROPFIND`。

Why：
- 某些 NAS、反向代理、登录网关或非 collection 路径，完全可能对 `OPTIONS` 返回成功，但对 `PROPFIND` 不返回可用目录项。
- 这会造成非常符合用户描述的状态：
- 顶部已显示连接成功
- 但文件区没有任何可见内容

代码证据：
- [WebDAVDataSourceAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift#L43)
- [WebDAVDataSourceAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift#L196)
- [FileBrowsingViewModel.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/ViewModels/FileBrowsingViewModel.swift#L104)

#### 3. 地址规范化可能把请求落到错误的 scheme 或路径

What：
- WebDAV 地址如果不带 scheme，会被默认补成 `http://`。
- 地址会被拆成 `host/port/path` 后再重建。
- 后续浏览请求也会基于这个规范化后的路径继续构造。

Why：
- 对 HTTPS-only、强依赖重定向、或路径编码要求严格的服务器，这种规范化可能把请求导向错误 transport 或错误 collection path。
- 这种问题不一定直接报错，也可能表现为：
- 连接阶段能通过
- 但列目录落到不正确位置
- 最终显示为空或不稳定

代码证据：
- [ConnectionInfo.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Domain/ValueObjects/ConnectionInfo.swift#L31)
- [ConnectionInfo.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Domain/ValueObjects/ConnectionInfo.swift#L88)
- [WebDAVDataSourceAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift#L248)
- [WebDAVDataSourceAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift#L295)

#### 4. 自目录过滤可能把返回结果静默清空

What：
- 适配器会主动丢弃“规范化后与当前请求路径相同”的条目，避免把当前目录自己显示在结果里。
- 目前针对“只返回当前目录自己”的保护主要针对单条结果。

Why：
- 如果服务器返回多个其实都指向当前目录本身的别名，例如 `/dav` 和 `/dav/`，这些条目可能全部被当成 self entry 丢弃。
- 这种情况下，结果会变成空数组，但不一定抛出明确错误。
- 用户最终看到的就是静默空目录。

代码证据：
- [WebDAVDataSourceAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift#L95)
- [WebDAVDataSourceAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift#L132)
- [WebDAVDataSourceAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift#L363)

#### 5. `href` 解析失败会直接丢项，而且是静默的

What：
- 每个返回项都要先把 `href` 解析成 `URL`。
- 解析失败的项会在 `compactMap` 中被直接丢弃。

Why：
- 如果服务器返回的 `href` 带未转义空格、中文、特殊字符，或使用某些 Foundation 不接受的相对 URI 形式，解析可能失败。
- 一旦所有返回项都因 `href` 解析失败被丢弃，界面仍会表现为空，而不是报出一个明确的协议兼容性错误。

代码证据：
- [WebDAVDataSourceAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift#L91)
- [WebDAVDataSourceAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift#L127)
- [WebDAVDataSourceAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift#L330)

#### 6. 文件类型过滤会制造“假空目录”

What：
- 文件浏览当前只展示可播放视频。
- 允许扩展名范围较窄：`mp4`、`mkv`、`avi`、`mov`、`m4v`、`webm`、`ts`、`m2ts`、`flv`。

Why：
- 如果当前目录下只有非视频文件，或者文件扩展名不在允许列表内，`files` 会被全部过滤掉。
- 只要 `folders` 同时因为目录识别问题拿不到，最终画面就会是完全空白。
- 因此文件过滤不是唯一根因，但它会显著放大目录识别问题的可见后果。

代码证据：
- [FileFilter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Domain/ValueObjects/FileFilter.swift#L15)
- [WebDAVDataSourceAdapter.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Adapters/WebDAV/WebDAVDataSourceAdapter.swift#L98)
- [FolderListView.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Views/FolderListView.swift#L46)

#### 7. 某些失败状态会留下“已连接 + 空列表”的误导性 UI

What：
- 连接阶段成功后，ViewModel 会保存活动远程适配器。
- 后续刷新如果失败，会清空 `files` 和 `folders`，但当前活动数据源仍可能保持为已连接状态。

Why：
- 这样用户在视觉上会持续看到“Connected to ...”，同时内容区已经被清空。
- 这会强化“明明连上了但服务器里什么都没有”的印象，即使底层真实原因其实是 refresh/listing 失败。

代码证据：
- [FileBrowsingViewModel.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/ViewModels/FileBrowsingViewModel.swift#L124)
- [FileBrowsingViewModel.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/ViewModels/FileBrowsingViewModel.swift#L180)
- [FileBrowserView.swift](/Users/xiongzhipeng/Applications/XrPlayer/XrPlayer/FileBrowsing/Views/FileBrowserView.swift#L34)

#### 8. 当前测试无法证明真实 WebDAV 目录枚举是正确的

What：
- 现有 WebDAV 测试主要覆盖未连接、非法地址、基础错误文案等。
- 没有针对真实 `207 Multi-Status` 的解析测试。
- 也没有覆盖 `href` 变体、`collection` 识别、远程文件夹渲染链路。

Why：
- 这不是运行时根因，但它解释了为什么这类 bug 能在数轮改动后依然存在。
- 当前测试集无法拦截“连接成功但目录枚举逻辑错误”的问题。

代码证据：
- [V03Tests.swift](/Users/xiongzhipeng/Applications/XrPlayer/Tests/XrPlayerCoreTests/V03Tests.swift#L204)

### 当前最高概率解释

当前最强解释是：

- 服务器确实返回了目录项
- 但这些目录项没有被当前实现稳定识别为 folder
- 或它们的 `href` 在本地解析/规范化后被静默丢弃
- 剩余落入文件分支的项又被视频扩展名过滤掉

于是最终出现“连接成功，但目录为空”的结果。

### 尚未被真实响应证实的未知项

- 目标服务器的 `207 Multi-Status` 是否为子目录返回了明确的 DAV `collection` 信息
- 子目录 `href` 是否带尾随 `/`
- 是否返回了多个其实都指向当前 collection 本身的别名
- `href` 是否包含空格、中文、`%`、`#` 或其他编码敏感字符
- 用户输入地址是否省略了 `https://`，从而被规范化成错误的 `http://`
- 目标目录是否主要由子文件夹、非视频文件或不在 allowlist 内的媒体文件组成

### 调查状态

- 状态：已归档
- 结论类型：历史排查记录，问题已从当前活跃已知问题中移除
