# Enchron 已知问题归档（已修复）

归档日期：2026-03-10

## 收口结论

- ✅ 统一播放启动入口已收口到 `PlaybackLaunchCoordinator`，`FileBrowsingViewModel`、`PlaylistView` 和 smoke 启动路径不再各走一套。
- ✅ SMB 配置流已切换为“仅输入 IP，连接后选择 share”，不再要求手填 `smb://ip/share`。
- ✅ `UserDefaultsStore` 与 `SwiftDataStore` 已不再是 `fatalError("TODO: implement")`。
- ✅ `MediaFolder.dataSourceID` 已改为稳定透传真实数据源 ID。
- ✅ SMB 凭证 key 不再因“先 host-only 登录、后选择 share”而漂移。
- ✅ `MediaFolder.id` 已不再是每次 listing 随机生成，而是稳定身份。
- ✅ HDR 内容识别的误报已明显收敛；`hdrOutputMode` 也不再在未验证 surface 时谎报 `passthroughHDR`。

以下条目从主文档移出，不代表整个大方向已经彻底完成，只代表这些具体问题不再需要继续占据主清单。

---

## 归档条目

### RES-001：播放启动路径分叉，失败时会留下错误的“正在播放”UI 状态

已修复点：

- 浏览器选中文件、播放列表点播、smoke 自动播放现在都统一经过 `PlaybackLaunchCoordinator`。
- 启动失败时，会回滚 `appModel.stopPlayback()`，不再继续保留错误播放态。

### RES-002：SMB 仍要求手填 share 名

已修复点：

- SMB 地址输入现在只接受 IP 地址。
- 连接成功后先枚举 share，再由用户选择 share 进入浏览。

### RES-003：Persistence adapter 仍是 `fatalError("TODO: implement")`

已修复点：

- `UserDefaultsStore` 已可读写用户偏好。
- `SwiftDataStore` 已提供最小可用的 progress / screen position 读写。

### RES-004：`MediaFolder.dataSourceID` 不是稳定语义

已修复点：

- Local / WebDAV / SMB 三条路径都已改为透传稳定数据源 ID。

### RES-005：SMB 两段式配置后凭证 key 漂移

已修复点：

- SMB 凭证 key 已改为 host 级稳定键，不再随着 share 变化。

### RES-006：`MediaFolder.id` 每次刷新都变化

已修复点：

- `MediaFolder.id` 已改为由 `dataSourceID + path` 派生的稳定身份。

### RES-007：HDR 识别误报与输出模式文案不诚实

已修复点：

- HDR 内容识别已收紧，不再把 BT.2020 标记直接视为 HDR 已成立。
- `hdrOutputMode` 现在只有在已验证的 HDR surface 存在时，才会报 `passthroughHDR`；否则退回 `previewSDR`。

---

## 说明

- 本归档文件记录的是“具体问题已从主清单移出”的结论。
- 与这些条目相关的更高层产品目标若仍未完成，会继续以新的开放问题形式保留在主文档中。
