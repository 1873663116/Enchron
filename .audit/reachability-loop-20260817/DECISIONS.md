# 可达性收尾循环决策记录

用户指令（2026-08-17 深夜）：持续派遣 Codex，实现应用内可达性承诺——除系统域、物理输入与人的感知项外，应用内一切操作可自动化触达；不改变 UI 语义与操作；循环直到目标完成；维护本决策记录。

起点状态：main `340e87fc`。矩阵 376 格 = 94 操作 × 4 呈现态：62 可达 / 152 已知缺陷 / 162 语义不适用。基线锁 62 格不可回退。CI 端到端已实证（运行 32040568692 success，quick gauntlet 在 runner 上真实执行并 PASS）。

## 2026-08-17T15:0x Z — 第三轮派遣编成

缺陷格构成与打击顺序判断：

1. **Docked 40 格**：全部被同一产品缺陷压制——Docked 转换期播放表面失去渲染像素，约 17 秒后 `lifecycle=failed`、`surfaceNoLongerViable`（证据 reachability-round2-20260818/raw/169 第 363-402 行）。这不是测试通道缺陷，是播放表面生命周期缺陷；修掉它一次性解锁最大的一组格，同时消除真实用户会遇到的播放失败。按"先复现再修复"派设备独占任务。
2. **SMB 表单清单缺口**：子控件 identifier 运行时拼接，清单生成器未展开，操作根本不在 376 格口径内——承诺覆盖"一切操作"，清单缺口必须先补。生成器修订是纯代码工作，不需要设备，可与 1 并行；新格一律以"已知缺陷"入基线，设备证明前不得转绿。
3. **系统 Menu 通用子项、其余 Window/Portal/Panorama 条件态格**：需要设备，排在任务 1 释放设备之后（第四轮）。

并行度决策：设备同一时刻只归一个任务（任务 1）；任务 2 明令禁触设备。两任务各自工作树（wt-docked-surface、wt-inventory-smb），均基于 main `340e87fc`，vendored FFmpeg 已复制。

约束（写入两份任务书）：不改变 UI 语义与操作；探针一律 `#if DEBUG`；构建产物全部在 /Volumes/Cortisol；REPORT.md 与 final-code.diff 落工作树根目录不入提交；测试基线按失败名对照（218 项、三个既定失败名、ProRes 偶发单独重跑裁决）。

已派出：任务 A（Docked 表面生命周期，设备独占）task_id `097ea4aa-70cf-4829-b598-a9332132926a`；任务 B（清单 SMB 展开，禁触设备）task_id `e28243d9-fc01-4de2-8e68-0845d000bed8`。完成后验收顺序：先到先审；合并串行进 wt-integration main，每次合并后全量 gauntlet 再推送。任一任务转绿的新格锁入基线。第四轮（设备排队中）：系统 Menu 通用子项经 --label 点击+具名产品探针路线、其余 Window/Portal/Panorama 条件态格、以及任务 B 新增格的设备证明轮。

## 2026-08-17T16:0x Z — 第三轮验收与合并

任务 A 验收通过。根因定案：Docked 的 RealityKit world 场景资源名错位三处（代码找 `world`/`skybox` 且从 main bundle 加载；实际资源为 RealityKitContent bundle 的 `Immersive` 场景与 `SkyDome` 实体）；world 加载失败使 `PlaybackSurfaceAnchor` 永不出现，新 renderer 无锚点，30 秒 settlement 截止（`presentationSettlementDeadline`）后败于 `surfaceNoLongerViable`——原报告的"约 17 秒"是日志截取点到截止点的剩余时间。修复经真机三级证据验证（worldLoad 探针、renderer 像素 3840×2160、诊断终态 attached=docked、截图）。Docked 40 格定向复测被 CoreDevice appDataContainer 文件服务故障（7000/120s deadline/StreamingAction 失败，设备本身 paired+unlocked）阻断三轮，任务方拒绝把不完整轮次写入基线——判定正确，基线保持 62/152/162。错误面板动词 `showPlaybackIssue` 经 `setUserVisibleIssue` 单点，未破坏错误所有权门禁。

任务 B 验收通过。我独立逐格比对：528 格中旧 376 格内容与判定零变化，新增 152 格全部 known-defect，62 可达格无回退。生成器对"不可枚举前缀/不透明拼接 helper"改为大声失败，符合声明形状纪律；7 项生成器回归测试入 quick gauntlet。

合并决策：A 快进、B 真合并。冲突两处：TestCommandChannel 两个新动词（showPlaybackIssue/showFileBrowserError）并存保留；清单 JSON 以合并后源码重跑生成器为权威（输出恰为 227 模板/132 操作，漂移检查通过）。runner 自动合并，py_compile 与生成器测试通过。合并提交 aa314ac6。全量 gauntlet 后台运行中，通过即推送。

第四轮编成（单一设备任务，等推送后派出）：先证通道（appDataContainer 探针取回恢复；不恢复即报告为阻塞）→ Docked 定向轮（world 修复后 40 格）→ 新增 152 格四态证明轮（runner 驱动路径已就位）→ 系统 Menu 通用子项 label 点击路线 → 其余条件态格。只有三级证据齐全的格转绿。

合并态全量 gauntlet PASS（结构检查升至 14 项，含任务 B 的生成器回归测试）。已推送 `340e87fc..aa314ac6 main` 与两条工作分支。第四轮已派出：task_id `aac41d4e-ca46-4509-8c77-671a67b73e65`（wt-reach4，设备独占；任务书含通道恢复阶梯：halt 重建→清残留进程→允许重启设备一次）。循环节律：30 分钟查一次派遣状态；上一次 ScheduleWakeup 因会话中断未触发，已知机制风险，靠用户在场时的手动唤醒兜底。

## 2026-08-18T01:0x Z — 循环状态

verification-quick 在 aa314ac6 上 success（运行 32080600518），CI 钥匙串修复连续两次推送验证成立。第四轮设备轮运行中：通道已恢复并进入新增格证据采集（格式编辑器 Apply 探针取回偶发 60 秒无产出，runner 按 150 秒单次拷贝上限自行收敛，未人为干预）。

2026-08-18T01:3x Z：第四轮运行中。任务动用了授权的设备重启一档（探针通道再度劣化），重启后从 Window 态重启轮次。未干预。

## 2026-08-18T02:0x Z — 第四轮验收与第五轮编成

第四轮验收通过并快进合并（main 1437d67c）。独立复核：528 格中 74 可达/292 缺陷/162 不适用，零回退，12 个新格全在 Docked（world 修复直接兑现）。验收要点：runner 聚合里 5 个证据不足的格被任务方主动拒收（menu 子项点击链未完成、unmetCapability-dismiss 不可命中）；Window 轮因通道故障产生 7 个假回退被整轮作废；resident-window 假回退根因是首次 toggle 响应文件被 CoreDevice 7000 吞掉，修复为先读 cleanup 反向状态再判定（232c2a42），不放松层级隐藏要求。

关键机制结论入账：系统 Menu 无 identifier 子项可用 label 定位且 isHittable、点击返回成功，但产品选择处理器探针（menu.item.*）从未出现——XCUITest 点击成功不构成 SwiftUI Picker binding 执行的证据。此结论直接决定菜单族格的路线：走 DEBUG 等价动词进产品选择处理器。

设备通道判定：devicectl 层面设备可见且配对正常；故障集中在 XCTest bootstrap（exit 74、readyTimeout、kAMDRemoteConnectError/IXRemoteErrorDomain 5）与 appDataContainer 文件服务（7000、120s deadline），呈间歇劣化，一次设备重启未根治。属系统域基础设施问题，不是应用内可达性缺陷。策略：给通道休整窗口，期间派非设备任务推进。

第五轮编成：任务 C（菜单选择动词，禁触设备）已派出，task_id `3646eb61-2e30-498e-85d1-199715326e18`（wt-menu-verbs）：DEBUG 动词进入与用户点击相同的产品选择处理器，覆盖全仓同形状菜单宿主，runner 判定路径与测试一并交付。其合并后派第六轮设备任务：Window/Portal/Panorama 完整轮＋新增 152 格＋菜单动词证明＋Docked 余格。

2026-08-18T03:0x Z：verification-quick 在 1437d67c 上 success（运行 32087009419，连续第三绿）。任务 C 运行中（清单生成器漂移处理阶段）。

## 2026-08-18T03:4x Z — 任务 C 验收与第六轮准备

任务 C 验收通过并快进合并（main ec032692）。独立复核：基线 552 格（74/316/162），旧 528 格零变化，新增 24 格全为 known-defect；新文件 DebugMenuSelection.swift 整体 `#if DEBUG` 且已入 xcfilelist。交付覆盖 12 个产品菜单宿主（声明形状全仓清点，排除 DesignPreview 标本与 segmented 样式），listMenuItems/selectMenuItem 两动词经与用户点击相同的产品闭包/Binding，选择在处理器返回后才记录成功；runner 判定保持"具名父菜单存在+可命中+动词进共享处理器且产品探针确认"三级。清单 228 模板/138 操作。全量 gauntlet 后台运行中，通过即推送并派第六轮设备任务（wt-reach6 已备）。

2026-08-18T04:0x Z：合并态全量 gauntlet PASS，已推送 1437d67c..ec032692 与 work/menu-selection-verbs。第六轮设备任务已派出：task_id `8e0fe832-28b4-4aa1-83f2-d366fba65b89`（wt-reach6）。范围：Window 完整轮＋菜单动词四态证明＋Portal/Panorama 轮＋Docked 余格＋连接表单格；通道纪律沿用第四轮教训（先证通道、恢复阶梯、部分完成可交付、中断轮次作废、74 格不得回退）。

2026-08-18T04:3x Z：verification-quick 在 ec032692 上 success（32090361463，连续第四绿）。第六轮运行中：Window 轮连接表单与来源菜单段推进正常，SMB 错误路径取证以产品探针为准、未误判为传输故障。

## 2026-08-18T05:3x Z — 第六轮验收与第七轮编成

第六轮验收通过并快进合并（main 10313f40）。零格转绿但判定纪律完全成立：唯一完整的 window-post-reboot 轮观察到 27 个候选可达格（连接表单十格、来源菜单九格、错误对话框两格、多选移动、PlayerUI Video Format 五格、两个菜单命令格），但四个旧可达格未在该轮重证触发无回退门禁，候选全部拒收；修复 runner 后的补跑轮在末段通道停滞，按"中断轮次作废"弃用。基线保持 74/316/162 零改动（diff 独立确认）。

有效交付为六项 runner 根因修复（先红后绿测试齐备，Scripts/verification 单测 22 项）：①先取 offset 再紧凑执行显示控件+点击，消除探针往返吃掉自动隐藏窗口；②Video Format 父操作要求产品 open 探针；③resetState 确定化（建 Reachability Fixture，defaults 清理先于建目录）；④单呈现态 --accept-baseline 只替换选中呈现态——原实现会用默认缺陷格覆盖其他三态基线，这是可能静默毁掉基线的隐患；⑤仅对幂等列举重试一次，选择动作不重试；⑥Video Format 场景后先 seekNormalized 再驱动 transport，避免片尾 Forward disabled。

通道结论升级：劣化模式为"长会话+大量文件往返后约 150 步左右停滞"，会话重建与设备重启只能短暂恢复，单次大轮已不可行。第七轮策略改为**分段轮**：runner 支持按操作子集分段执行，每段独立 session＋前后通道健康探针，段结果合并；交付级无回退门禁=合并结果中被驱动过的旧可达格全部重证、未覆盖格不改判、有回退即整交付拒收。候选 27 格与四个旧格优先入段。Emby 版本/季节格允许使用设备上既有 Emby 源（历史轮已用过），禁止新增外部连接；Emby 不可用时保留缺陷并记录。

2026-08-18T05:5x Z：合并态全量 gauntlet PASS，已推送 ec032692..10313f40 与 work/reachability-round6。第七轮已派出：task_id `d38b368f-99b7-4973-a15d-bfb84c3d73c0`（wt-reach7，分段轮架构：段级健康探针+段结果合并+交付级无回退门禁；先架构后设备；优先重证四旧格与 27 候选格；分段计划完整留档；架构工作先行也给通道自然休整窗口）。

2026-08-18T06:3x Z：verification-quick 在 10313f40 上 success（32099555810，连续第五绿）。第七轮设备分段执行中：第 3 段（Manage add 系列与错误动作隔离，段内约 60 动作），至今无恢复阶梯事件——分段架构对通道劣化的规避初步起效。

## 2026-08-18T08:0x Z — 第七轮验收与第八轮编成

第七轮验收通过并快进合并（main ab7bff3a）。独立复核：105/285/162，零回退，+31（Window 29、Portal 2）；SettingsScreen 探针经既有 setter 且 #if DEBUG。分段交付架构成立：七个合格段（各自独立 session、前后健康探针、段内连续性）、交付级无回退门禁 accepted=true、四个第六轮旧格全部重证；作废段全部有据（未登记产品证据、通道停滞、旧 session 串戏）。本轮设备重启一次，恢复阶梯最终在面包屑段用尽。

新事实：Portal 真机层级不存在 PlayerPanel-menu-more 父宿主——DEBUG 菜单处理器可送达，但 Accessibility 父节点缺失，属产品可达性缺陷（承诺定性），第八轮修。Settings 五个菜单处理器已证明但清单没有五个独立操作格（后续清单修订项）。

第八轮编成（单任务，先产品修复后设备分段，给通道休整）：①产品侧暴露 PlayerPanel 菜单父宿主 Accessibility 元素（可访问性事实修正，不改 UI 语义）；②面包屑段补跑（场景已就绪）；③Portal 余格、Panorama、Docked 分段推进；④Emby Version/Season 段（用既有源）。

2026-08-18T08:2x Z：合并态全量 gauntlet PASS，已推送 10313f40..ab7bff3a 与 work/reachability-round7。第八轮已派出：task_id `1631f02f-eca7-4399-8725-2140a7395453`（wt-reach8）。范围：PlayerPanel 菜单父宿主可达性修复（先行）＋Settings 清单展开＋面包屑补跑＋Portal/Panorama/Docked 分段＋Emby Version/Season 段。

2026-08-18T08:5x Z：verification-quick 在 ab7bff3a 上 success（32107972474，连续第六绿）。第八轮进入 Panorama 段：transport/seek/四菜单族产品探针已取得；一次清理点击的 ready.json 取回超 80 秒，任务方按连续性门禁语义自行处置。

## 2026-08-18T10:0x Z — 第八轮验收与语义裁决

第八轮验收通过并快进合并（main bca8cd3c）。独立复核：572 格（Settings 五操作展开，+20 格），114/281/177，零回退，+9 可达（Window 5 个 Settings 菜单、Panorama 4 个菜单族格）；净产品代码差异为零（无效的 PlayerPanel modifier 修改已在轮内撤销）。四个合格段被接纳；面包屑段因旧格未重证被合并预检正确拒收；Docked 三次尝试与 Emby 段死于通道，恢复阶梯（含一次设备重启）用尽。

语义裁决（第九轮执行）：PlayerPanel 菜单族在 Window/Portal 应改判**语义不适用**，依据是生产代码结构——FusedPlayerPanel.moreMenu 只由 playerControlDockControls 实例化（Panorama/Docked 专用），Window/Portal 走 WindowPlaybackControls 且菜单功能经 PlayerUI-TopAction-more 已可达。任务方给出的另两个选项（ornament 加控件、TopAction 双 Accessibility 身份）分别改变布局与制造重复语义，均违反"不改变 UI 语义"约束，否决。推广为通用规则：呈现态适用性从生产代码的渲染结构推导（谁在哪个呈现态实例化哪个内容），推导不出即大声失败；不再依赖人工假设。

第九轮编成：①适用性推导精化（生成器/分类器，macOS 可验证，先行）；②Docked 余格、面包屑补跑、Panorama 余格、Emby Version/Season 分段（通道休整后）。

2026-08-18T10:2x Z：合并态全量 gauntlet PASS，已推送 ab7bff3a..bca8cd3c 与 work/reachability-round8。第九轮已派出：task_id `3ec512c4-7d76-4e11-a0bc-29b94f7fd07e`（wt-reach9）。范围：适用性推导精化（渲染结构推导通用规则，PlayerPanel 菜单族 Window/Portal 改判）＋Docked 小段化补跑＋面包屑段（含可能的面包屑可命中性产品修复）＋Panorama 余格＋Emby 段。

## 2026-08-18T晚 — 用户裁决：矩阵坐标轴纠正

用户否决"全部操作 × 四呈现态"的矩阵结构：四种呈现态是播放时的状态，只有播放域的行为随呈现态变化，且播放控件是复用的；Media Library、Emby、Settings 等浏览域操作发生在主窗口浏览语境，与播放呈现态正交，不应乘以四。现行 572 格中 177 个"不适用"格正是坐标轴错误的症状——本不该存在的格被当作 N/A 填充携带。

重构方向（第十轮执行，第九轮的渲染结构推导正是其地基）：浏览域操作 × 1（主窗口浏览语境证明一次）；播放域操作 × 推导出的实际渲染呈现态集合（控件复用不免除逐态证明——同一控件在 ornament/attachment/dock 不同容器中的可命中性与送达是不同的运行时事实，历史轮次已证明）。第九轮在途不打断：其适用性推导是重构地基，其设备段证明的操作证据在新坐标轴下依然有效。

2026-08-18T晚：原第九轮任务 3ec512c4 被会话中断连带取消（已跑 26 分钟，留下四个有效提交：渲染宿主适用性推导等；孤儿设备控制器进程已终止）。CI 在 bca8cd3c 上 success（32118335727，连续第七绿）。第九轮按坐标轴裁决重编成并派出：task_id `89a7214d-6ad1-4b30-9716-ff259b2b4690`（wt-reach9 原分支续作）：坐标轴重构先行（浏览域×1、播放域×推导语境集合、114 格证据映射迁移且不得回退），再在新口径下分段设备证明（Docked 小段、面包屑含潜在产品修复、Panorama、Emby）。

2026-08-18T晚（循环）：第九轮重编成任务 89a7214d 运行中，处于第三次重建尝试。循环提示词已按用户指示去状态化：可变状态唯一权威来源为本决策记录。

## 2026-08-18T晚 — 第九轮验收：坐标轴重构落地

第九轮验收通过并快进合并（main 4d08c564）。独立复核：199 判定点=浏览域 86×1＋播放域 46×推导语境子集＋共享命令 2×5；110 可达/89 缺陷；82 个旧可达操作全部存续零回退；产品代码零改动（纯脚本与配置）。重构质量要点：五份旧证据被发现坐标错误（旧矩阵把控件的目标呈现态误当渲染语境，如 PlayerUI-TopAction-dock 实际渲染在 Window 顶栏）并带原因码重定向；9 个声明未实例化的 identifier 被分类留档而非静默丢弃或伪造格；迁移器可重放。审计缺口如实记录（残留进程检查未存进程表输出）。

设备侧本轮仅一段合格（9 点重证），通道在重启后仍持续停滞，恢复阶梯用尽。剩余 89 缺陷点全部为设备证明待办：主窗口浏览 40、Window 9、Portal 13、Panorama 8、Docked 19；19 段/149 点分段计划已就绪。

第十轮编成：①证据通道暴露面缩减（macOS 先行）——把"每动作一次 devicectl 文件往返"改为段末批量取回或控制器内联携带，目标是单段 devicectl 调用数下降一个数量级，直接攻击通道停滞的触发条件；②通道休整后按 19 段计划推进设备证明。

2026-08-18T晚：合并态全量 gauntlet PASS，已推送 bca8cd3c..4d08c564 与 work/reachability-round9。第十轮已派出：task_id `820de970-4fd8-4aa2-beaf-4defd521f21f`（wt-reach10）。范围：证据通道暴露面缩减先行（段末批量取回、命令响应合批、快照瘦身，目标单段 devicectl 调用数降一个数量级，离线判定与在线判定 verdict 一致性测试），随后按 19 段计划推进设备证明（Docked→主窗口浏览含面包屑→Panorama→Window/Portal 余点→Emby）；残留进程检查的进程表输出必须落盘（修复第九轮审计缺口）。

## 2026-08-18T夜 — 第十轮验收：通道改造兑现，设备段全数合格

第十轮验收通过并快进合并（main 24095112）。独立复核：199 判定点坐标集与第九轮一致，110→121 可达、89→78 缺陷，零回退，11 个新增点与报告逐条相符（主窗口浏览 5：SourcesSidebar-sourceMore、MediaLibrary-Breadcrumb-current、Manage-addFiles、Manage-addPhotos、presentation-conversion-dismiss；Docked 6：menu-more/speed/subtitles/{category}-{item.id} 与 listMenuItems/selectMenuItem）。产品改动仅限 TestCommandChannel.swift，整条通道由 ENCHRON_TEST_CHANNEL 门控，新增证据 session 探针 #if DEBUG，无视图代码改动。

通道改造兑现：证据取回由逐动作往返改为段末批量，最长段 51→4 次调用（12.75 倍），全计划 373→70 次（5.33 倍，因 19 个短段各自的固定成本与 Panorama 段的安全分片而低于单段倍数）。效果是 19/19 段一次通过、无拒绝段、无设备重启——通道停滞不再是本轮的限制因素。作废尝试全部有据（runner 键错误、离线响应解码缺陷、场景语境错误、探针 629KB 越过 600KB 上限、段末复制遇 7000、Emby 扫描 169 步后 stop 失败），修正后重跑。

新事实：探针文件存在安全上限，长段需中点归档；Emby 候选扫描需设上限（收敛为 12）；合并器改为跨合格段聚合，较晚段的缺陷观察不再覆盖较早段的合格可达证据。

第十一轮编成（task_id `86a1e8c4-b0cc-4876-bec3-99baada63472`，wt-reach11，基线 24095112）：先对剩余 78 点按障碍性质分类，再据此新编分段计划——①状态诱发类（playbackIssue/unmetCapability/spatialFailure/loadFailure 浮层跨语境，PlayerPanel 的 audio/episodes/media-information-close/exit-spatial），不能由普通操作或既有动词诱发的按 setUserVisibleIssue 单写纪律补动词；②内容依赖类（VideoFormat 一族需真实格式选择与 HDR 回退片源，Emby Season/Version/Episode/StillCard 需剧集条目，只用设备既有源）；③界面状态类（多选删除、新建与重命名文件夹、网格与列表条目、侧边栏行、前进后退、Settings 分类、scroll、EnvironmentCard 一族与 environmentVolume）；④疑似产品缺陷（FileBrowsing 面包屑两点连续多轮不在层级内，同名 MediaLibrary-Breadcrumb-current 已可达可作对照，允许修正可访问性事实但不得改 UI 语义）。要求对清不掉的点给出定性结论：内容条件不满足／产品可访问性缺陷／通道未覆盖／语义不适用。

2026-08-18T夜：合并态全量 gauntlet PASS（20260818T134905Z-52629），已推送 4d08c564..9db47165 与 work/reachability-round10。分支推送首次被 pre-push 的 quick gauntlet 拦下，报新失败名 `audioRendererFailureRetiresAudioAndVideoContinues`（PlaybackCoreTests.swift:3290-3294，lastFailure 与 audioRendererState 快照尚未落定）；隔离复跑三次全通过，判定为与 ProRes 同类的负载下偶发——当时第十一轮委托正在并发构建。按既有隔离复跑规则放行，不写入既定失败名单；若再次出现应改为在测试内等待快照落定而不是延长超时。

## 2026-08-19 — 第十一轮验收与 runner 判定缺陷裁决

第十一轮验收通过并合并（main ea2c49b5，因决策记录提交在前，分支先 rebase 再快进）。独立复核：199 点坐标集不变，121→124 可达、78→75 缺陷，零回退，新增三点（SMB Connect、Window 的 playbackIssue-confirm 与 unmetCapability-dismiss）与报告一致；identifier 模板 228→225（移除三个覆盖子控件的 Emby 父容器 identifier），操作仍 134。

产出只有 +3，原因不在设备通道，而在一个 runner 判定缺陷，我已独立定位并核实：`tap()` 无条件为目标记录 exists/hittable 观察却不评估送达，于是任何"作为导航步骤"的点击都把一个矩阵操作判成 known-defect，进而触发无回退门禁使整段不能交付。第十一轮 browser-01/-02/-05/-06 四段的 deferred replay 全部 passed、计划目标三级证据完整，全部因此白丢。反证：browser-05-emby-content-attempt4 把 `Emby-Navigation-Tab` 点了六次判为缺陷，而同段 segment-after-surface-probe.log 里有六条 `navigation tab delivered tab=emby`——产品送达了，runner 从未拿探针评估它。

裁决：驱动而未评估送达的结果是"未评估"，不是"缺陷"。修法方向是让操作携带送达探针期望，使每次 tap 自动用延迟探针评估送达，导航性点击顺带免费重证旧点，正是无回退门禁想要的。四段可用磁盘上既有证据离线重算，不需要真机时间。browser-03-settings-category 属另一性质（17 条 delivery 仅 2 条通过验证，证据确实不全），不予挽救——第十一轮末尾新增的"replay 全部 delivery 必须验证通过"门禁本身是对的。

同轮另两项裁决：①`BreadcrumbView`、`FolderListView`、`FileBrowserSidebar` 经核实在 Apps 与 Modules 内无任何生产调用点，其六个点应由生成器按第九轮规则归档为 uninstantiated 并退出操作清单、收缩矩阵分母，而不是在报告散文里标"语义不适用"。②Emby 会话约束更新：登出后重连设备上已配置的同一服务器不属于"新建外部连接"，原约束意图是不引入新外部依赖而非冻结会话，故 Emby-Connection 四点与 SignOut 可证，前提是先确认 Keychain 凭据可恢复并在同段内证完登出与重连。

第十二轮已派出：task_id `347e6a72-5aa2-4f58-8910-6ee251501502`（wt-reach12，基线 ea2c49b5）。范围：runner 判定缺陷修复与回归测试先行→四段离线重算→uninstantiated 归档→Emby 会话与 fixture 内容条件复核→两个系统 alert 输入框 identifier 缺陷（只做不改 UI 语义的修法）→未运行的 14 段真机证明与 Window HDRFallback 段。

## 2026-08-19 — 第十二轮验收：判定缺陷修复兑现，矩阵 194/152/42

第十二轮验收通过并合并（main 9c90c8cc，分支先 rebase 再快进）。独立复核：分母 199→194（归档 5 点全部原为缺陷，无可达点被归档掩盖），124→152 可达、75→42 缺陷，零回退，28 个新增与报告逐条相符（浏览 19、Window 4、Portal 5）。产品 Swift 改动仅 DEBUG：Emby 送达探针、同服务器身份 SHA-256 摘要动词；凭据走本机凭据文件、不进命令行、证据经清洗，仓库未新增任何文件。

判定缺陷修复兑现：tap 观察与送达评估分离（tappedCells / unassessedTappedCells / drivenCells / applicationReceived），只有明确送达评估进入门禁；旧 schema 证据按实际 delivery 重新分类。第十一轮被误拒的四段离线重算回收 14 点，其中 browser-05 七点全收、browser-01 只收 2/13、browser-06 只收 2/8——选择性接纳说明规则没有被放宽成"全收"。browser-03-settings 仍不接纳（17 条 delivery 仅 2 条验证通过），需重跑。

两项真机证伪：①系统 alert 输入框的显式 identifier 修法无效，visionOS 把 SwiftUI alert 桥接成系统层级、子控件 identifier 不保留，无效改动已撤回——与系统 Menu 剥离子项 identifier 同类，第十三轮按既定办法用 DEBUG 动词进同一处理器与 Binding 证明送达。②"既有远程源根目录为空"是选错了源，另一个既有 WebDAV 源根目录有 7 个文件夹与 1 个视频，那批浏览点条件具备。归档纠正一处：我预估 6 个未实例化点，实际 5 个，`FileBrowsing-Breadcrumb-current` 属生产在用的 PathBreadcrumbMenu，不可归档且已证明可达。

设备通道仍是唯一硬约束，且触发条件已量化：Portal 重复入场时探针四个 marker 内由 68,651 涨到 636,660 字节越过 600,000 上限；改为每两标记检查后，仍在 504,471 字节归档时遇 CoreDevice 7000 socket 关闭。裁决：缩短归档间隔是追着体积跑，第十三轮改为让产品侧 DEBUG 探针落盘自身有界，使段内取回变成小而恒定的读取。

2026-08-19：合并态全量 gauntlet PASS（20260819T014445Z-50922）。第十三轮已派出：task_id `edbdf37c-fc4a-4747-b2bb-39f64872c86c`（wt-reach13）。范围：探针有界化先行→系统 alert 两点走 DEBUG 动词→浏览域余点（含用"新建指向同一既有服务器的条目再删除"证明 SourcesSidebar-delete、Settings 段重跑、Emby Version 全库 128 项确定结论）→未运行的 13 段（Portal routes/issues、Panorama 五段、Docked 五段、Window 媒体信息与环境卡片）。

## 2026-08-19 — 第十三轮验收：通道问题收口，剩余障碍转为产品可访问性

第十三轮验收通过并合并（main 55f4631c 前的分支 rebase 后快进）。独立复核：194 点坐标集不变，152→168 可达、42→26 缺口，零回退，16 个新增（浏览 7、Portal 6、Window 2、Panorama 1）。产品 Swift 改动经查全部为 DEBUG 门控：新增 DebugProbeJournal、各处 recordReachability 探针体在 #if DEBUG 内（Release 为空操作）、FilesScreen 的 alert Binding 请求类与观察者整体在 #if DEBUG 内、PlaybackVideoSurface 的改动是探针去重签名与 2 秒心跳（只影响日志量），物理设备 Release 构建通过。

探针有界化兑现且量化：硬上限 196,608 字节、压缩目标 131,072，19 个最终段峰值 196,564（差 44 字节），每段仅 1 次探针取回，对照第十二轮 portal-01-dv 的段末 491,799 字节与 12 次取回、现场残留 1,284,191 字节。判定事实不参与截断，仅事实即溢出时整段作废。重要区分：本轮仍有一次 28,813 字节探针复制触发 CoreDevice 7000——"大文件必然失败"与"CoreDevice 可独立失败"就此分开，通道不再是主要限制因素。

Emby 多版本条件彻底了结：递归只读扫描 1,081 项（996 Episode、83 Movie、2 Video），MediaSources.count 最大为 1，多版本项为 0，产品仅在计数大于 1 时显示 Version，故为内容条件不满足而非缺陷。第十二轮的 128 是顶层库项数，不是完整目录。SourcesSidebar-delete 亦查清：可见菜单项与 DEBUG 动词都进 performDeleteSelection，该处理器只进入选择模式，真正删除是另一动作，因此无需删除设备数据即可证明。

剩余 26 点的性质已改变，主体是产品侧可访问性事实缺失：层级未暴露 20、存在但不可命中 3、系统 alert 桥接 2、内容条件 1。分布规律构成线索：media-information-close 四语境全缺席；错误与失败浮层动作目标在 Window/Portal 可达而在 Panorama/Docked 全缺席（同一问题入口已被调用）；EnvironmentCard 一族只在 Docked 缺席而 Window 已可达；menu-audio 与 menu-episodes 只在沉浸语境缺席。裁决：第十四轮不再排段重复观察，先把症状还原为机制（渲染在哪个 scene、挂哪个宿主、XCUITest 元素树是否包含该子树、isHittable=false 是碰撞体/遮挡/traits），再按机制修可访问性事实；判别"系统边界"与"我方缺陷"的判据是同样内容在别的语境能否暴露。

工作树卫生问题一处（我方失误）：第十三轮 worktree 因相对路径落在 wt-integration 内部，交付物两份。已用绝对路径重建，nested worktree 已移除，REPORT.md 归档到证据目录。

第十四轮已派出：task_id `112ebe1a-f725-4c97-8f46-70e2d0c6f5da`（wt-reach14，基线 55f4631c）。

## 2026-08-19 — 第十四轮验收：机制诊断兑现，设备锁定挡住终局回归

第十四轮部分验收并合并产品修复（main 05b899f7）。任务方守住关键纪律：因 19 段防回退回归未执行（设备进入 needs-to-be-unlocked 锁定态），基线保持 168/26 未动，18 个新增三级证据只存于交付物，待回归通过后才接纳 186/8。合并的是产品修复本身（构建、结构、Python 门禁全过）。

三项机制诊断与修复，全部有真机证据：①沉浸问题浮层此前挂在 ImmersiveSpace 的 RealityView attachment 上，SwiftUI 系统 alert 不进入 application 元素树——Window/Portal 同策略可暴露而沉浸语境不能，排除 identifier 与策略本身；修法是由常驻 volumetric Window 承载 alert，presentation owner 改变而 UI 语义不变，Panorama/Docked 八个 action 全部转为三级可达。②Docked 环境卡入口绕过 AppModel 转场初始化，执行器拿到空时间门放弃后自旋重领同一请求（1 秒 706 次 replacementPrepared）；修后走同一初始化、volume 不再注册竞争执行器、同 identity 刷新保留 lease，Docked EnvironmentCard 五点全部可达——这同时是真实产品缺陷修复。③展开媒体信息容器的 identifier 覆盖子元素，四语境全缺席的共同机制是 SwiftUI identifier 传播而非内容条件；用 .accessibilityElement(children: .contain) 保留双方身份，Window/Portal/Panorama 三点可达。exit 按钮的 isHittable=false 是 controls=hidden 状态问题而非遮挡，Panorama 已证；Portal CustomAngle 是原生 Picker 系统边界（坐标事件无有效 scene ID）。Docked 的 menu-more 查询触发 XCUITest 使 App 崩溃且设备重启后复现，属可复现系统边界。

剩余 8 点：Docked 四点（media close、audio、episodes、exit）纯因设备锁定未跑，机制与修复已就绪；其余四点为确证的系统边界或内容条件（CustomAngle、两个系统 alert 输入框、Emby Version）。

阻塞与处置：设备解锁是物理输入，属用户封闭清单项，已通知用户。等待期间派出测试门修复任务 task_id `ea9c7281-dfc4-4a32-ae74-ac2b385f0246`（wt-testgate）：TrackSelectionPreferenceTests 找不到 package 级 MediaStateStore/PersistedMediaState，经查为 main 上既有阻断，与第十四轮无关。第十五轮待设备解锁后派出：19 段防回退回归＋Docked 四点终局段＋接纳 186/8 基线。

2026-08-19：结构检查失败定性为检查编码旧架构——playback-surface-structure 要求环境卡 volume 注册 SpatialPlatformEffectExecutor，而第十四轮修复正是取消该竞争注册；已把检查改为新不变量（volume 根不得注册执行器、三执行器均在 App scene），guard 自测通过，全量 gauntlet PASS，main 420c274c 与第十三、十四轮分支已推送。

测试门修复验收合并（main c751fe9e）：根因是 package unit 名不一致——Xcode 把本地 Swift package 编译为 -package-name <工作树目录名>，而 EnchronDomainTests 硬编码 -package-name enchron_emby，故 package 级类型不可见；修法改为 $(SRCROOT:base:identifier)，可在任意工作树成立。附带修一处 Xcode beta Swift Testing 宏兼容（#require 内 mutating 调用先存局部变量）。真机验证：TrackSelectionPreferenceTests 24 项、PlaybackPresentationStateTests 105 项、全目标 313 项（排除需私有凭据的 EmbyLiveIntegrationTests）全部通过。Swift 测试执行门恢复。重要信号：该任务在物理设备上完成全部测试，设备已解锁。

第十五轮终局已派出：task_id `f10e06bf-06e6-496e-a739-68162a8397fe`（wt-reach15，基线 c751fe9e）。范围：168 点防回退回归（产品代码在第十四轮改动过，必须当前构建重证）→设备锁定前未跑的四个 Docked 点→合并第十四轮 18 个证据接纳新基线（预期 190/4）；剩余应只有四类确证边界（Portal CustomAngle、两个系统 alert 输入框、Emby Version），若发现可清则证明之。

## 2026-08-19 — 第十五轮终局：194 点 190 可达，承诺达成

第十五轮验收通过并合并（main 83c7f13e）。独立复核：194 点坐标集不变，168→190 可达、26→4 缺陷，零回退。**Window、Panorama、Docked 三个语境已 100% 清零**（32/0、22/0、31/0），Portal 25/1，主窗口浏览 80/3。本轮零产品代码改动（纯脚本与配置）。

回归覆盖是本轮的核心交付：33 段/172 计划判定，168 个旧可达点中 163 个由当前构建物理设备重证，另 5 个由无回退门禁覆盖（Docked menu-more、Emby Season Picker 与 Season 条目、MediaLibrary error-dismiss、Portal unmetCapability-dismiss），未覆盖旧可达点为 0，unassessedLegacyDrivenCells=0。静态门禁的设计经查是收紧而非放宽：要求相关产品文件整文件哈希未变、精确代码区段未变、无工作树修改，且只允许覆盖旧基线中已为 reachable 的点；若当前设备证据报告带证据的缺陷，静态证明不得覆盖设备事实。

四个 Docked 点全部证成：media-information-close 走完整三级；menu-audio 与 menu-episodes 复用历史合格段的父按钮两级事实＋当前 session 的 DEBUG closure 送达，未展开系统 Menu（该 attachment 的 targeted snapshot 与合成展开会终止 App，是已确证系统边界）；exit-spatial 先证 presentation=docked/controls=shown/controlsInteractive=true，再经按钮共用的 requestPlaybackPresentation 处理器，并证 Window 终态。

轮内又抓到两个同源 runner 判定缺陷并补了单元测试：准备性 app 命令登记到无关证明语境、跨语境命令登记；均按纪律要求真机重跑而非以代码测试替代设备证据。段 08/15/19 出现建立连接前挂起，定性为自动化基础设施疲劳（设备保持解锁、无授权拒绝特征），重启设备一次后恢复。

剩余 4 点全部是有机制证据的边界，非"未评估"：Emby-Detail-Version（1,081 项递归扫描多版本项为 0，运行时内容条件不满足）、两个系统 alert 输入框（visionOS alert bridge 不导出 identifier，显式方案已证伪，同 Binding 送达已证但不满足三级判定）、Portal CustomAngle（原生 Picker 节点存在且 enabled、frame 48×44 但 isHittable=false，坐标事件返回无效 scene ID 并终止 runner）。四者都无法在不改变 UI 语义、布局与交互的前提下清除。

承诺状态：除系统域、物理输入与感知项外，应用内操作可自动化触达并证实送达——已达成。剩余 4 点落在系统边界与内容条件，属承诺的封闭清单范畴，不构成我方未兑现项。若将来要动它们，路径是产品自有 sheet 替换系统 alert（改 UI 语义，需用户裁决）与显式按钮组替换原生 Picker（同上），以及获得多版本 Emby 内容。
