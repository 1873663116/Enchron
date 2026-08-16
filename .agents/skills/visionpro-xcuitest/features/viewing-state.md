# 观看进度与续播

再次打开看过的视频，从上次位置继续。写向哪里由 Viewing State Authority 决定：本地与 File Source 来源写 Enchron 持久化，Emby 来源回报服务器且不落本地盘。

## Sub-features

- 退出播放时保存位置。
- 再次打开时从该位置续播。
- 看完的媒体标记为已看完，不再续播。
- Emby 的 Resume 与 Play from Beginning 两个入口分别尊重与忽略服务器进度。
- 设置页 Playback Progress 一行可整体清除本地进度。

## How to get to it (user POV)

播放到中途退出，回到媒体库再次点开同一视频。Emby 侧在单集详情页出现 Resume 按钮。设置页的 Playback Progress 行提供 Clear All。

## Driving it with the controller

```sh
# 播到某处后退出
C app-command --verb toggleControls
C tap --identifier PlayerUI-InfoBar-button-back
# 再次打开，读诊断串的 position
C tap --identifier <网格卡片标识>
C snapshot --identifier PlayerUI-window-control-plane --no-screenshot
```

干净态取证要先 `app-command --verb resetState` 清 `enchron.*` 键，再重启，否则内存中的库会在下一次变更时把旧引用重新持久化。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 位置按 Media Identity 存取，Content Revision 变化时不误用旧进度；Emby 来源不写本地 | 模拟器单测（MediaStateStore 相关） |
| 结构 | 退出路径确实提交了 `PlaybackSessionReport` | 模拟器单测 |
| 物理 | 二次打开的诊断串 `position` 落在上次退出附近而非 0 | 真机 |
| 物理 | Emby 侧进度出现在服务器（而非本地） | 真机加服务器侧查询 |
| 感知 | 不适用 | |

## 证明的终态

二次打开后诊断串 `position` 非零且接近上次退出值，`lifecycle` 进入 Playing。Emby 侧另需在服务器查到该条目的播放位置已更新，本地容器内不应出现对应记录。

## Gotchas

- 已看完的判定与续播是两件事，看完的媒体应从头播；取证时别用刚好播到结尾的片源。
- 退出播放后浏览位置回到 Media Library 根，二次打开远程文件要从侧栏重走目录。
