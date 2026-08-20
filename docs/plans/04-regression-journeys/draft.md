# 真机回归旅程集（初稿 v2，逐条审改用）

## 合同

一次全绿授权的完整话术：「以下旅程全部通过；另有 N 个声明过而无人看守的证据点（附录 A）、M 个未完成的人工感知项（附录 B）、K 个内容条件缺口（附录 C）。」绿灯只对旅程负责，三个附录是绿灯明示不覆盖的范围，每轮报告必须原样携带。

执行语义：每条旅程从干净状态开始，旅程之间不传递状态，任何一条可单独重跑。旅程内某步失败即中止本旅程，其后步骤记为未评估而非缺陷；已通过步骤的证据保留。通道故障或内容条件不满足导致的中止记为「作废」，不计缺陷。可达性矩阵保留为第 0 层，仅三种情况运行：源码变动波及判定点锚点、旅程步骤以「够不着」签名失败、明确要求全量审计。

## 判读模型（2026-08-20 裁决：不设参照帧体系）

判读分三层，分界规则是「这个断言的真假由谁决定」：

**机械层（脚本断言）**：结构化字段的相等与阈值判断。lifecycle、position、session 身份、audioTrack、投影与立体字段、EDR 余量、服务器侧进度。真假由代码决定，出错即失败，无裁量。

**判断层（Agent 判读）**：不可写成机械规则的情境判断，依据两类采集：
- 内部采帧：间隔至少 1 秒截 3 帧。判读内容是否真实（非纯色、非黑屏、非冻结）、帧间是否连续（证明持续解码）、有无整体色偏（P5 紫绿类在截图上直接可见）、HDR 片有无未解释 PQ 的灰雾形态。
- 麦克风采集：麦克风置于扬声器旁，采集后经音频分析工具输出结构化结果（主导频率、静音段、粗同步），Agent 判读结论。生成向量的每条音轨带独特脉冲频率（如 880Hz 对轨 1、440Hz 对轨 2），轨道切换的可闻性因此可机判。
- **判读者自检**：每轮判读开始前，先判一组已知阴阳样本（furyroad-with-dv 与 stripped 对照）。判不出已知坏样本，本轮全部判断层结论作废。

**人工层（佩戴者）**：亮度是否足够、饱和度偏好、空间化跟手感、切换突兀感、舒适度、真实手势。配合模式沿用既定裁决：Agent 供片单与「每部看什么」，用户任意顺序手点，Agent 后台记录。

## 基元动作库

每个基元写明输入、执行、成功判据、失败行为。旅程步骤以「P编号(参数)」引用。

**P0 会话与通道前置**
执行：ensure-session 新起常驻 XCTest 会话（旅程之间不复用会话）；探针健康检查：写入随机内容、取回、SHA256 比对、清空。
成功：会话就绪且探针往返一致。失败：本旅程作废（通道故障，不计缺陷），进入恢复阶梯（会话重建→残留进程清理→设备重启一次；重启后以 devicectl 的 passcodeRequired 与 unlockedSinceBoot 字段判读状态，Xcode 错误字符串不构成终局证据，等待后重试）。

**P1 干净开场(起始页签)**
执行：通道动词 resetState(libraryFolder="Journey Fixture")——先删内存库中全部媒体引用（防止退出时回写持久化）、回到根后逆序删全部库文件夹、删全部 enchron.* 前缀 UserDefaults、新建指定空文件夹；不触碰 TestMediaInbox（harness 暂存区）。然后 relaunch（terminate 加 launch）；tap 对应 Navigation-Ornament-tab-*，探针确认 delivered tab=目标。
成功：库为空且仅含指定文件夹；应用落在目标页签。失败：旅程作废。

**P2 注入媒体(文件名, 目标文件夹)**
执行：app-command importMedia——应用把 TestMediaInbox 中同名文件入库。应答须 ok:true 且载荷含文件名。若应答「暂存区无此文件」：devicectl copy 从主机 fixture 源推送该文件后重试一次。最后 listLibrary 复核引用存在。
成功：库列表与网格均出现该媒体。失败：内容条件未满足，旅程作废（不计缺陷，报告列入附录 C 现场核对项）。

**P3 开播到稳态(卡片 identifier, 预期呈现)**
执行：P10 包裹下 tap 网格卡片；轮询诊断串直至 lifecycle=Playing 且呈现字段等于预期；上限 40 秒。随后立即执行 P8（采帧判读）确认真实内容。
成功：稳态达成且 P8 判读通过。失败：本步失败（40 秒未稳态、或 P8 判黑屏/纯色/冻结）。

**P4 唤控件点按(目标 identifier 或 label)**
执行：先通道动词 show_controls，确认 chrome 元素回到层级；单目标用 tap，连续多目标必须用 tapSequence（控件自动隐藏窗口撑不过多次通道往返）；每次点按经 P10 送达判定。
成功：目标送达。失败：目标不在层级或不可命中→记「够不着」签名（触发第 0 层定向重证），本步失败。

**P5 菜单选择(宿主菜单, 目标项)**
执行：P4 打开父菜单。子项有 identifier 且可命中→直接 tap 加 P10。系统 Menu 剥离子项 identifier 时（已证系统边界）→ DEBUG 动词 listMenuItems 确认目标在列，selectMenuItem 进入与用户点击相同的产品处理器，探针确认 menu.item 送达。
成功：产品选择处理器探针出现。失败：XCTest 点击返回成功但探针未出现，判本步失败——点击成功从不是送达证据。

**P6 进入 Docked(环境名)**
前提：播放稳态且投影为 Flat。执行：P4 以 tapSequence 连点 TopAction-dock 与 DockMenu-指定环境；轮询 PlayerUI-spatial-state 直至九项空间事实全部成立（attached=docked、renderer 像素非零、surfaceSettled=true 等），上限 30 秒（presentationSettlementDeadline）。
成功：九项俱真。失败：本步失败并存快照。

**P7 经格式编辑进入 Panorama(投影, 立体)**
执行：P4 打开 videoFormat 编辑器（产品 open 探针确认，不以面板出现为准）；P5 语义选投影与立体（identifier 含度数符号原样拼接）；tap apply → 同时满足：presentation=portal、attached=portal、transition=none、pendingSpatialEffect=none、投影/立体/revision 已更新、Portal 请求 1280×720。再 P4 点 TopAction-resumePanorama → 沉浸探针 settle=true 且 RealityKit 采用所选投影。
成功：两段各自判据全部成立。失败：任一字段不满足即本步失败（禁止只看部分字段）。

**P8 采帧判读(场景预期)**
执行：控制器截图 3 张，间隔至少 1 秒。机械预检：分辨率非 1×1、非纯色直方图（继承「工具报成功但输出垃圾」教训）。Agent 判读：内容真实、帧间连续、无整体色偏、符合场景预期（如 HDR 无灰雾）。判读结论与帧一并归档。
成功：机械预检过且判读通过。失败：判读不通过为本步失败；预检不过为证据无效（重采一次，再不过旅程作废）。

**P9 音频判读(预期特征)**
执行：麦克风采集不少于 5 秒 → 音频分析工具输出结构化结果 → 与预期特征比对（预期频率主导、非静音、或指定切换后频率变化）。
成功：特征匹配。失败：静音或特征不符为本步失败。

**P10 送达判定(操作 id)**
执行：动作前记录探针偏移 → 执行动作 → 取探针增量查找预期送达标记 → 三级记录：存在层级、可命中、应用已送达。三者俱全才记通过。
纪律：驱动而未评估送达 = 未评估，永不记缺陷；本判定是唯一写入点，任何步骤不得旁路。

**P11 终态核对(预期清单)**
执行：回到预期界面；诊断串无 userVisibleIssue；旅程涉及的持久化状态逐项复核（listLibrary、设置值、进度）；本旅程证据段末批量取回归档。
成功：清单全部成立。

---

## J01 本地媒体：从导入到卡片留影（完整详述）

覆盖：media-import、clean-state-playback、cache-and-artwork（Artwork 侧）。
内容条件：sdr-bframe-multiaudio-avsync-30s.mp4（双 AAC 轨，880/440Hz 脉冲）。

1. P0；P1(files 页签)。
2. P2(sdr-bframe-multiaudio-avsync-30s.mp4, "Journey Fixture")。网格出现 MediaLibrary-grid-video-sdr-bframe-multiaudio-avsync-30s.mp4。
3. P3(该卡片, window)。机械层：lifecycle=Playing、videoVisible=true。判断层：P8(SDR 真实内容)。
4. P9(880Hz 主导、非静音)——音画皆在解码，判断层收口。
5. 轮询诊断串至 position≥10 秒。
6. P4(PlayerUI-InfoBar-button-back) 退出播放 → 回到网格，无错误浮层。
7. 采网格卡片区域截图，Agent 判读卡片画面是否为退出前后的画面内容【判断层·此前无人看守，本步建立看守】。
8. P11(库中恰一条引用；无 userVisibleIssue)。

不证明：Files 选择器与相册两条系统面导入入口（人工层，佩戴者场次各走一遍即终身有效）；画质主观。

## J02 WebDAV：从连接到续播（完整详述）

覆盖：remote-source-connection（WebDAV）、viewing-state（本地权威）。
内容条件：既有 WebDAV 服务器（旅程开始前主机侧探活：请求根目录列表成功；目标目录与视频名由探活结果确定）。凭据自本机凭据文件读取，不进命令行，证据经清洗。

1. P0；P1(files 页签)。
2. P4(FileBrowsing-SourcesSidebar-sourceMore) 打开来源菜单 → P5(该菜单, addWebDAV) → 表单出现：SourceConnection-webDAV 的 name/address/username/password/connect 五控件均在层级。
3. 逐字段 typeText 填入（每字段经 P10：产品侧绑定值变化由探针或表单回读确认）。密码字段确认层级中不回显明文。
4. tap connect → 成功判据：面包屑显示「WebDAV · 地址」且侧栏出现新 source 条目。若出现错误表达：本步失败并存错误截图（错误路径的正向验证归 J03）。
5. tap 新侧栏条目进根目录 → 机械层：FileBrowsing-FilesScreen-itemCount 数值与层级中卡片计数一致。
6. 按探活得到的路径逐层 tap --label '目录名, folder' 直至含视频目录；每层 itemCount 复核。
7. P3(目标远程视频卡片, window)；P8；P9(非静音)。
8. 轮询至 position≥60 秒；P4(InfoBar-button-back) 退出。
9. 再次 tap 同一卡片 → 机械层：position 在退出值 ±5 秒内且 lifecycle=Playing（本地续播权威）。
10. P11(侧栏含该来源；无 userVisibleIssue)。证据清洗复查：凭据值、URL userinfo、Authorization 头在全部归档中零命中。

不证明：证书信任询问（附录 D3 裁决前豁免）；凭据错误路径（J03）；服务器端行为（WebDAV 无进度协议，本地持久化即权威）。

## J05 画面解释：动态范围家族（完整详述，新判读模型）

覆盖：picture-interpretation（动态范围轴）。
内容条件：SDR=J01 片源；HDR10=HDR10.MP4；HLG=HDRMovie.mov（注意其含两条 hevc 流，判读时以实际选中流为准）；P5=Emby 唯一 P5 条目（用前探活）；P7 FEL=FEL_test_for_AVS.mkv（拆基础层按 HDR10 呈现是既定行为，判读预期按 HDR10）；P8.1=P81_GlassBlowing2；P8.4=Patterns_Of_Nature_HLG-P8.4 UHD；P10=DASH .mpd 入口；P20=HLS main.m3u8。

0. **判读者自检（先于一切家族）**：打开 furyroad-with-dv 与 furyroad-stripped 各采一帧，Agent 盲判哪个带 DV 元数据呈现差异。判错→本旅程全部判断层结论作废，只保留机械层记录。
1. P0；P1(files 页签)。
对每个家族 f（本地片走 2a，流媒体与 Emby 走 2b）：
2a. P2(家族片源) → P3(卡片, window)。
2b. Emby：进 Emby 页签按 J04 步骤 1 到 3 打开对应条目；DASH/HLS：经其清单入口打开【入口形态待核对：产品当前如何接受 .mpd/.m3u8，若无入口则该家族记内容条件缺口】。
3. 机械层：FormatDescription 的动态范围字段与片源声明一致；EDR 余量等呈现字段在诊断串中读取【附录 D6：字段是否已暴露待核对，未暴露则此项列无人看守】。
4. 判断层：P8(家族预期)——真实内容、连续、无整体色偏、HDR 无灰雾；帧与判读结论归档为本轮证据。
5. P4 退出，回网格。
终态：九家族各有机械层加判断层双通过记录。P11。

人工层残留：每家族一次「亮度与饱和度是否符合预期」（附录 B1）；确认过即长期有效，此后每轮只跑机械层加判断层。

## J07 呈现态环游（完整详述）

覆盖：mode-transitions、controls-summon、format-editing。
内容条件：sdr-bframe-multiaudio-avsync-120s.mp4（窗口与 Docked 段，时长足够从容操作）；180_3D_loop10.mp4（Panorama 段）。

1. P0；P1(files 页签)；P2 两片皆注入。
2. P3(120s 片, window)。
3. P4(PlayerUI-window-playback-surface) 点视频表面 → chrome 回到层级（TopAction 族可见）——窗口态控件唤出的真实用户路径。
4. P7'(校验分支)：P4 打开 videoFormat 编辑器（open 探针确认），确认当前 Flat，tap cancel（送达确认）→ 保持 Flat 以进 Docked。
5. P6(skybox)。九项空间事实成立后：P8(Docked 下真实内容)；P9(非静音)。
6. Docked 内 P5(menu-more, 媒体信息) 展开 → P4(PlayerPanel-media-information-close) 关闭（送达确认；展开容器不遮蔽子元素 identifier 是round 14 修过的行为，回退即失败）。
7. P4(PlayerPanel-button-exit-spatial) → 机械层：presentation=window、attached=window、按有效逐眼画面比例重新锁定。
8. P4 退出播放；P3(180_loop10 片, 预期呈现【待核对现行为：产品对已知全景格式的首开呈现是 window 还是直接 portal；初稿按需要经编辑器设置起草】)。
9. P7(180°, SBS) → Portal 稳态四字段加 1280×720，再 resumePanorama 至沉浸 settle。
10. Panorama 内控件往返：通道 toggleControls 显示 → 探针序列 firstPoseApplied→visible=true；层级含 PlayerPanel-controls；再 toggleControls 隐藏 → visible=false，残留语义节点 isHittable=false；全程无 Window Scene 操作。真实捏合唤出归人工层（判据 toggle source=spatialTap，合成点击不带该语义，不能代替）。
11. P4(面板 Return to Portal) → portal 稳态。
12. P7''(Flat, Mono) 经编辑器改回 → presentation=window、比例锁定。
13. 通道 seekNormalized(0.97) → 播放至自然结束 → 机械层：lifecycle=ended 保持；层级含 Replay；P8(最终帧为真实内容非黑)。
14. tap Replay → position 归零且 lifecycle=Playing。
15. P11。
16. 【附录 D1 裁决后并入】Docked 面板 Advanced Settings 宿主改一次格式，与窗口菜单宿主进同一产品处理器。

不证明：切换过程主观突兀感（人工层）；注视加捏合真实手势（人工层一次）。

---

## J03 SMB / J04 Emby / J06 立体投影 / J08 轨道 / J09 网络韧性 / J10 存储设置 / J11 库管理 / J12 错误面

（v1 紧凑版内容保持有效，粒度批准后按 J01 至 J07 同等粒度详述。v1 各表见 git 历史或直接要求展开。）

---

## 覆盖率台账

| 特性 | 旅程 |
|---|---|
| media-import | J01、J11 |
| remote-source-connection | J02、J03 |
| emby-library | J04 |
| clean-state-playback | J01 |
| picture-interpretation | J05、J06 |
| track-selection | J08 |
| viewing-state | J02、J04、J10 |
| network-resilience | J09 |
| mode-transitions | J07 |
| format-editing | J07 |
| controls-summon | J07 |
| cache-and-artwork | J01、J10 |

## 附录 A：无人看守证据点

1. media-import：Files 选择器路径（人工层场次）
2. picture-interpretation：EDR 余量等呈现字段若未暴露（D6 核对后定）
3. track-selection：不支持/失败音轨的感叹号表达（缺样片）
4. network-resilience：三条（J09 全部，待 E1 至 E4 界面实现）
5. cache-and-artwork：Artwork 留影（J01 步骤 7 建立看守）
6. 未声明缺口四处：SMB/WebDAV 错误路径（J03 建立）、证书信任询问（D3）、看完标记与 Clear All（J10 建立）、外挂字幕独立证据（J08 建立）

## 附录 B：人工层清单（每项一次，此后由机械层加判断层代理）

1. 九个动态范围家族的亮度与饱和度确认
2. 多声道头动空间化跟手感与音质主观评价（可闻性与轨道切换已归判断层机判）
3. 呈现态切换是否突兀、有无闪烁
4. 注视加捏合真实手势（docked 与 panorama）
5. Files 选择器与相册导入各走一遍
6. 180° 高分辨率片源目视确认前须先确认片源内容

## 附录 C：内容条件缺口

1. 不支持音轨样片缺失（感叹号表达无从验证）
2. DTS/TrueHD/Vorbis 本地样片为零（TrueHD 仅 Emby 条目，会漂移）
3. MV-HEVC 可操作时长不足（仅 4 秒，无循环拷贝）
4. 平面内容循环片缺失（呈现切换连续场景只有 180/360 三件）
5. Apple Immersive（AIVU）容器语料为零（是否列为需求维度待定）
6. 远程外挂字幕与 Emby external stream 无本地语料
7. DASH/HLS 清单入口的产品形态待核对（J05 步骤 2b）

## 附录 D：需裁决与核对项

1. format-editing 双宿主：README 与特性文件不一致（J07 步骤 16 按两宿主起草）
2. cache-and-artwork 索引判据的自动化程度：正文与表格矛盾
3. 证书信任询问无 identifier：产品可访问性缺陷（修）还是系统域豁免
4. Emby 海报墙 swipeUp 一次杀 runner：未定性，需根因
5. Emby 系列详情页顶部播放图标无 identifier 且点按无效：疑似产品缺陷
6. EDR 余量等呈现字段是否已在诊断串暴露（老积压项，J05 依赖）
7. 全景片首开的默认呈现行为（J07 步骤 8 两分支择一）
