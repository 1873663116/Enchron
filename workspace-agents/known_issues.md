# Enchron 已知问题

更新时间：2026-03-10

已归档并标记为已解决：

- [known_issues_2026-03-06_resolved.md](/Users/xiongzhipeng/Applications/Enchron/workspace-agents/archive/issues archive/known_issues_2026-03-06_resolved.md)
- [known_issues_2026-03-08_resolved.md](/Users/xiongzhipeng/Applications/Enchron/workspace-agents/archive/issues archive/known_issues_2026-03-08_resolved.md)
- [known_issues_2026-03-10_resolved.md](/Users/xiongzhipeng/Applications/Enchron/workspace-agents/archive/issues archive/known_issues_2026-03-10_resolved.md)

当前主文档只保留仍开放、且对当前产品判断有指导意义的问题。

---

## KI-007：首播黑屏仍在 5 秒量级，且切换视频时旧画面 / 旧控件会残留到新视频首帧出现前

### 现象

- 2026-03-11 最新用户实测：首次启动应用打开视频时，黑屏加载仍然大约需要 5 秒。
- 同样是在第一次启动，打开“i”二级面板时，会有一阵严重的卡顿，之后便不再发生。

用户的推测：可能需要参考之前归档过的处理办法，你又一次把非必要的可以后台处理的任务变得需要显式处理了，导致第一次打开的严重卡顿

---

## KI-010：HDR 内容识别已经更准确，但 HDR 入口、切换能力和真实输出都还没有成功

### 现象

- 用户 2026-03-10 明确确认：HDR 内容类型本身现在识别更准了。
- 与此同时，当前真实输出仍然只是 `SDR Preview`，而且正式的 HDR / SDR 的按钮点击，但不具备真正的播放对应hdr视频的能力

---

## KI-011：SMB 现在能够正常连接，也能够读取服务器内的文件夹，文件夹目录中的文件夹是点不开的