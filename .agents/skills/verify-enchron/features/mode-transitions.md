# 呈现切换

四个呈现：window、portal、docked、panorama（`PlaybackPresentation.swift`）。可达性受内容约束：dock 仅 window 且非全景内容；portal 仅全景内容；应用格式后按投影路由。

## Sub-features

- 打开落地（干净态按源分类；带持久覆盖按覆盖）。
- window → panorama（应用全景格式；历史间歇停滞路径，settle 判据走探针）。
- panorama → portal → panorama（面板 exit/enter 按钮）。
- window ⇄ docked（TopAction-dock + DockMenu；面板 exit）。
- 失败回滚：settle 超时 30 秒后干净回滚，不悬挂。

## How to get to it (user POV)

窗口 chrome 的 Dock 与 Video Format；panorama 内捏合召唤面板后 Return to Portal；portal 的 Resume/Enter Panorama。

## Driving it with playback_mode_matrix

入口切换（window→panorama 经格式应用）已无人化。面板按钮切换依赖捏合召唤，当前自动化不可达：settled 沉浸态层级只有入场元素，召唤的控件窗口不进层级（成因与处置见 visionpro-xcuitest 通道边界）。矩阵路径表保留这些路径定义（`--list-paths`），佩戴者在场时按同一标识执行即可对表验收。

## 证明的终态

每步以探针 settle（沉浸目标）或控制串稳态（窗口目标）收口；30 秒未 settle 应观察到干净回滚（presentation 回 window、lifecycle 走向 idle）而非悬挂。

## Gotchas

- teardown 型解散（回滚、连播失败）后主窗口场景输入死亡：元素命中但零投递，通道 ping 仍应答即可确诊；恢复只有重建会话，产品级修复（解散时重新激活场景）在案未落。
- 停滞是间歇事件且未随状态复现；探针里的 `modeRequestRetry` 行是每次恢复重请求的记录，出现停滞时先取它。
