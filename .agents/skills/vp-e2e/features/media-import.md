# 媒体导入

本特性覆盖媒体引用进入资料库的各条路径。所有生产入口最终都汇聚到 `mediaLibrary.addFiles(urls)` 这一个函数。

## Sub-features

- 通过 Files 选择器导入。这是真实用户的主路径，包含 iCloud Drive 的目录导航。
- 通过相册选择器导入。
- 验证用的注入路径：位于 TestMediaInbox 内的文件经由通道命令 `importMedia` 导入，走的是同一个 addFiles 入口。

## How to get to it (user POV)

用户在媒体库界面打开导入菜单（位于 `FileBrowsing-Manage-button` 一侧），由它打开 Files 选择器；选中文件后，该文件出现在媒体库网格中。

## Driving it with the controller

Preconditions: 会话已建立且 `ping` 有应答。注入路径还要求 fixture 已推入 App 容器的 `Documents/TestMediaInbox/` 目录。系统选择器路径要求 Device Hub 预检已经返回当前 Simulator 的 `targetBinding` 和可定位的 Fit 画布。

注入路径用于快速验证生产入库管线：

```sh
xcrun devicectl device copy to --device <CoreDevice> \
  --domain-type appDataContainer --domain-identifier com.xiongzhipeng.Enchron \
  --source <本地媒体> --destination Documents/TestMediaInbox/<名字>
python3 Scripts/verification/interactive_visionpro_ui.py --device <id> \
  --output-directory <dir> app-command --verb importMedia --arg file=<名字>
```

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 所有导入入口都汇聚到 `mediaLibrary.addFiles(urls)`；媒体引用被正确写入资料库并持久化 | 模拟器单测 |
| 物理 | 注入路径：`importMedia` 应答 ok，且媒体库网格中出现对应卡片 | 两条 lane 的产品通道 |
| 物理 | Files 与 Photos 选择器路径，包括跨进程系统界面和系统权限门 | Simulator Device Hub、选择结果和资料库快照 |
| 感知 | 不适用 | |

## 证明的终态

注入路径的终态是 `importMedia` 返回 `ok: true`，`listLibrary` 含有对应引用，且媒体库网格出现 `MediaLibrary-grid-video-<名字>` 卡片。系统选择器路径还必须绑定系统界面中的选择动作、App 收到的交付结果和相同的资料库终态。Files 选择器落在 App 窗口之后时，按[模拟器 lane](../references/simulator.md)记录的 Home 往返步骤把选择器带到前景。

## Gotchas

- importMedia 只接受 TestMediaInbox 的直接子文件名，含路径穿越的输入会被拒绝。
- 注入路径只覆盖入库管线。Files 与 Photos 选择器使用 Simulator Device Hub 单独覆盖，不能由注入结果替代。
