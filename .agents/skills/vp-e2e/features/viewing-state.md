# 观看进度与续播

本特性覆盖再次打开看过的视频时从上次位置继续播放的行为。进度写向哪里由 Viewing State Authority 决定：本地与 File Source 来源写入 Enchron 持久化，Emby 来源回报给服务器且不落本地盘。

## Sub-features

- 退出播放时保存当前位置。
- 再次打开同一视频时从该位置续播。
- 播放完的媒体被标记为已看完，之后不再续播。
- 存在历史进度时，本地与 Emby 都先弹系统 alert 让用户选 Resume 或 Play from Start；Resume 尊重进度，Play from Start 忽略进度，设置页的 Resume Playback 行对两者同样生效。
- 设置页的 Playback Progress 一行可以整体清除本地进度。

## How to get to it (user POV)

用户播放到中途退出，回到媒体库后再次点开同一视频，主窗口弹出 Resume Playback? alert，选 Resume 续播、选 Play from Start 从头播。Emby 单集详情页只有一个 Play 按钮，服务器有进度时弹同一个 alert。设置页的 Playback Progress 行提供 Clear All 操作。

## Driving it with the controller

Preconditions: 会话已建立；干净态取证需要先执行 `resetState` 再重启 App。

```sh
# 播到某处后退出
C app-command --verb toggleControls
C tap --identifier PlayerUI-InfoBar-button-back
# 再次打开，读诊断串的 position
C tap --identifier <网格卡片标识>
C snapshot --identifier PlayerUI-window-control-plane --no-screenshot
```

干净态取证必须先用 `app-command --verb resetState` 清除 `enchron.*` 键，然后重启 App；如果不重启，内存中的库会在下一次变更时把旧引用重新持久化。

## 证据

| 种类 | 判据 | 谁守 |
|---|---|---|
| 结构 | 播放位置按 Media Identity 存取，Content Revision 变化时不会误用旧进度；Emby 来源不写本地 | 模拟器单测（MediaStateStore 相关） |
| 结构 | 退出路径确实提交了 `PlaybackSessionReport` | 模拟器单测 |
| 物理 | 二次打开时诊断串的 `position` 落在上次退出位置附近而不是 0 | 真机 |
| 物理 | Emby 侧的进度出现在服务器上（而非本地） | 真机加服务器侧查询 |
| 感知 | 不适用 | |

## 证明的终态

终态是二次打开后诊断串的 `position` 非零且接近上次退出时的值，同时 `lifecycle` 进入 Playing。Emby 侧还需要在服务器上查到该条目的播放位置已更新，而本地容器内不应出现对应记录。

## Gotchas

- 已看完的判定与续播是两件独立的事：已看完的媒体应当从头播放，因此取证时不要使用刚好播放到结尾的片源。
- 退出播放后浏览位置会回到 Media Library 的根层级，因此二次打开远程文件时需要从侧栏重新走一遍目录。
