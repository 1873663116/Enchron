# 媒体导入

媒体引用进入资料库的路径。生产入口都汇于 `mediaLibrary.addFiles(urls)`。

## Sub-features

- Files 选择器导入（真实用户主路径，含 iCloud Drive 目录导航）。
- 相册选择器导入。
- 验证注入：TestMediaInbox 内文件经通道 `importMedia` 走同一 addFiles 入口。

## How to get to it (user POV)

媒体库界面的导入菜单（`FileBrowsing-Manage-button` 一侧）打开 Files 选择器，选中文件后出现在网格。

## Driving it with the controller

Files 选择器跨进程，XCTest 只能按语义 label 驱动且权限门需佩戴者（历史成功证据见 vp-e2e 的证据基线一节）。无人化验证用注入路径：

```sh
xcrun devicectl device copy to --device <CoreDevice> \
  --domain-type appDataContainer --domain-identifier com.xiongzhipeng.XrPlayer \
  --source <本地媒体> --destination Documents/TestMediaInbox/<名字>
python3 Scripts/verification/interactive_visionpro_ui.py --device <id> \
  --output-directory <dir> app-command --verb importMedia --arg file=<名字>
```

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 所有入口汇于 `mediaLibrary.addFiles(urls)`；引用正确入库并持久化 | 模拟器单测 |
| 物理 | 注入路径：`importMedia` 应答 ok 且网格出现卡片 | 真机通道 |
| 物理 | Files 选择器路径（跨进程，含权限门） | **待建**，需佩戴者场次 |
| 感知 | 不适用 | |

## 证明的终态

`importMedia` 响应 `ok: true` 且 payload 含该名字；`listLibrary` 复核；网格出现 `MediaLibrary-grid-video-<名字>` 卡片。

## Gotchas

- importMedia 只接受 TestMediaInbox 直接子文件名，拒绝路径穿越。
- 注入绕过的是选择器，不是入库管线；Files 选择器路径本身的回归仍需佩戴者场次覆盖权限门。
