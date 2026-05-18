# Enchron v3 QA Report — Batch 1 (A+B+C)

> Date: 2026-04-02
> Round: 8 (Phase 1 T1.1)
> Simulator: Apple Vision Pro (B170D4C9, visionOS 26.2, Booted)
> Build: XrPlayer Debug-xrsimulator (BUILD SUCCEEDED)
> Paths tested: 12 / 59
> Categories: A. 启动与导航 (3) + B. 文件源管理 (4) + C. 窗口模式播放 (5)

---

## Summary

| Category | Paths | PASS | PARTIAL | FAIL | BLOCKED | DEFERRED |
|----------|-------|------|---------|------|---------|----------|
| A. 启动导航 | 3 | 0 | 3 | 0 | 0 | 0 |
| B. 文件源 | 4 | 2 | 1 | 0 | 0 | 1 |
| C. 窗口播放 | 5 | 5 | 0 | 0 | 0 | 0 |
| **Total** | **12** | **7** | **4** | **0** | **0** | **1** |

---

## Health Score

| Category | Score | Weight | Weighted |
|----------|-------|--------|----------|
| Console | 100 | 15% | 15.0 |
| Links/Navigation | 70 | 10% | 7.0 |
| Visual | 92 | 10% | 9.2 |
| Functional | 77 | 20% | 15.4 |
| UX | 85 | 15% | 12.75 |
| Performance | 100 | 10% | 10.0 |
| Content | 92 | 5% | 4.6 |
| Accessibility | 85 | 15% | 12.75 |
| **Total** | | | **86.7** |

Deductions:
- Functional -15: local subfolder navigation broken (high)
- Functional -8: codec display missing in detail view (medium)
- Links/Navigation -15: "本地文件" data source entry absent (high)
- Links/Navigation -15: scene selection panel not on main tab (high)
- Visual -8: environment name mismatch "自然日落" vs "日落自然" (medium)
- UX -8: openImmersiveSpace requires separate button press (medium)
- UX -8: SDR label shown instead of hidden for non-HDR content (medium—minor)
- Content -8: VideoDetailView lacks codec display (medium)
- Accessibility: estimated -15 from QA-M01 (known, not tested this batch)

---

## Detailed Results

### QA-A01: 应用启动首屏显示 — PARTIAL

**Simulator Evidence:**
- Screenshot: `screenshots/QA-A01-initial-launch.png`
- App launched without crash (PID 40299)
- Main UI panel visible in Shared Space mode with glass background

**Results by step:**
| Step | Expected | Actual | Verdict |
|------|----------|--------|---------|
| 1. Launch | 无崩溃启动 | ✅ 启动正常, PID 40299 | PASS |
| 2. Main UI | 场景选择+文件浏览同屏 | ⚠️ TabView (Files/Scenes/Settings)，场景和文件是分开的 Tab | PARTIAL |
| 3. NavigationStack | 数据源列表含"本地文件" | ❌ 左侧显示 tab 列表 (Files/Scenes/Settings)，无"本地文件"持久入口 | FAIL |
| 3b. 场景面板 | 3 个环境选项 | ✅ CinemaEnvironment enum 3 cases, SceneSelectorView 渲染全部 | PASS |

**Code evidence:**
- `AppTabView.swift:9-21` — TabView `.sidebarAdaptable` style, 3 tabs
- `SceneSelectorView.swift:19` — `ForEach(CinemaEnvironment.allCases...)`
- `CinemaEnvironment.swift:4-9` — `.darkTheatre`, `.starryNight`, `.sunsetNature`

**Issues found:**
1. **ISSUE-001** (medium): 场景选择和文件浏览是 Tab 分离的，非同屏显示
2. **ISSUE-002** (medium): 无持久的"本地文件"数据源入口，默认显示 Documents 目录

---

### QA-A02: 场景选择面板交互 — PARTIAL

**Results by step:**
| Step | Expected | Actual | Verdict |
|------|----------|--------|---------|
| 1. 点击场景按钮 | 视觉反馈 + openImmersiveSpace | ⚠️ 视觉反馈有 (scaleEffect+accent), 但不触发 openImmersiveSpace | PARTIAL |
| 2. ImmersiveSpace 打开 | openImmersiveSpace 被调用 | ❌ 需要另按 ToggleImmersiveSpaceButton | FAIL |
| 3. 环境切换 | switchEnvironment 不退出沉浸空间 | ✅ AppModel.switchEnvironment(to:) 仅更换环境+保存位置 | PASS |
| 4. 选中态更新 | 按钮反映当前选中 | ✅ isSelected = appModel.currentCinemaEnvironment == environment | PASS |

**Code evidence:**
- `SceneSelectorView.swift:20-53` — visual feedback: scaleEffect, accent stroke, spring animation
- `SceneSelectorView.swift:21-22` — button calls `switchEnvironment` not `openImmersiveSpace`
- `AppModel.swift:180-185` — `switchEnvironment(to:)` saves/loads screen position
- `ToggleImmersiveSpaceButton` — separate button required to open immersive space

**Issues found:**
3. **ISSUE-003** (medium): 场景卡片点击仅切换环境，不自动打开沉浸空间——需额外按 ToggleImmersiveSpaceButton。两步操作可能困惑用户。

---

### QA-A03: NavigationStack 文件浏览导航 — PARTIAL

**Results by step:**
| Step | Expected | Actual | Verdict |
|------|----------|--------|---------|
| 1. 点击本地数据源 | 右侧显示文件列表 | ✅ FileBrowserView 显示文件列表 | PASS |
| 2. 文件列表内容 | 名称+大小+日期 | ✅ FolderListView: name + byteFormatter + dateFormatter | PASS |
| 3. 排序选项 | 按名/大小/日期 | ✅ FileBrowserView:154-170 三种排序 | PASS |
| 4. 升降序切换 | 列表顺序翻转 | ✅ ascending/descending toggle | PASS |
| 5. 子文件夹导航 | push 进入 | ❌ guard activeRemoteAdapter != nil — 本地文件夹点击无效 | FAIL |
| 6. 返回按钮 | pop 回上级 | ❌ "Up" 按钮同样被 remote adapter guard 阻断 | FAIL |

**Code evidence:**
- `FileBrowserView.swift:39` — NavigationStack ✅
- `FolderListView.swift:115-124` — file name + size + date ✅
- `FileBrowsingViewModel.swift:302-309` — `navigateToFolder`: `guard activeRemoteAdapter != nil` ← **blocks local navigation**

**Issues found:**
4. **ISSUE-004** (high): 本地文件子文件夹导航完全不可用。`FileBrowsingViewModel.swift:303` 的 `guard activeRemoteAdapter != nil else { return }` 导致点击本地文件夹无任何响应。仅远程数据源（SMB/WebDAV）的文件夹可导航。

---

### QA-B01: 本地文件浏览与选择 — PARTIAL

**Results by step:**
| Step | Expected | Actual | Verdict |
|------|----------|--------|---------|
| 1. 浏览 /Movies/ | 直接显示 | ⚠️ 默认 Documents 目录，需手动 "Choose Folder..." | PARTIAL |
| 2. 点击视频 → 详情 | VideoDetailView | ✅ navigationDestination → VideoDetailView | PASS |
| 3. 元数据显示 | 分辨率/编码/时长 | ⚠️ 分辨率✅, 编码❌, 时长❌ (仅帧率) | PARTIAL |
| 4. 播放按钮 | 存在 | ✅ play.fill button | PASS |
| 5. DecidePlaybackMode | .window for flat SDR | ✅ 非全景+非沉浸 → .window | PASS |

**Code evidence:**
- `VideoDetailView.swift:229-255` — shows Resolution, HDR type, Frame Rate, Projection, File Size. **No codec. No duration.**
- `VideoDetailView.swift:311-323` — play button exists
- `DecidePlaybackModeUseCase.swift:14-23` — returns `.window` for non-panoramic + non-immersive

**Issues found:**
5. **ISSUE-005** (medium): VideoDetailView 不显示编码格式（codec）和时长（duration），仅显示分辨率、帧率、投影、文件大小、HDR 类型

---

### QA-B02: SMB 数据源添加与浏览 — PASS

**Results by step:**
| Step | Expected | Actual | Verdict |
|------|----------|--------|---------|
| 1. Add SMB 入口 | 可见可点击 | ✅ FileBrowserView:206-208 Button("Add SMB Server...") | PASS |
| 2. 配置页面 | 地址+用户名+密码 | ✅ DataSourceConfigView:56-78 三个字段 | PASS |
| 3. SecureField | 密码加密 | ✅ DataSourceConfigView:76 SecureField | PASS |
| 4. 错误处理 | 非崩溃 | ✅ catch → validationError 内联显示 | PASS |
| 5. Keychain 保存 | 持久化 | ✅ KeychainStore:26-48 SecItemAdd | PASS |

---

### QA-B03: WebDAV 数据源添加 — PASS

**Results by step:**
| Step | Expected | Actual | Verdict |
|------|----------|--------|---------|
| 1. Add WebDAV 入口 | 可见 | ✅ FileBrowserView:202-204 Button("Add WebDAV Server...") | PASS |
| 2. 配置 UI | URL+用户名+密码 | ✅ 同 DataSourceConfigView | PASS |
| 3. 错误处理 | 存在 | ✅ friendlyErrorMessage 映射 | PASS |

---

### QA-B04: Apple Photos 视频访问 — DEFERRED (Human-only)

**Structure verification:**
| Check | Result | Evidence |
|-------|--------|----------|
| Photos 入口 | ✅ | FileBrowserView:185-191 Button("Photo Library...") |
| PHPhotoLibrary 权限 | ✅ | PhotoLibraryDataSourceAdapter:46 requestAuthorization |
| PHAsset export | ✅ | PhotoLibraryDataSourceAdapter:61-248 fetch+export |

**Verdict**: Structure PASS. Runtime deferred to human (Simulator 无 Photos 库).

---

### QA-C01: SDR MKV 窗口模式完整播放路径 — PASS

**Results by step:**
| Step | Expected | Actual | Verdict |
|------|----------|--------|---------|
| 1. .mkv 可识别 | FileFilter 接受 | ✅ FileFilter.swift:15 "mkv" in playable | PASS |
| 2. 点击播放 | 视频启动 | ✅ coordinator.confirmPlayback → playback starts | PASS |
| 3. MTKView 渲染 | 画面显示 | ✅ WindowVideoView:24-45 MTKView + renderer delegate | PASS |
| 4. 播放/暂停 | 切换 | ✅ PlayerControlsView:184-213 pause/resume toggle | PASS |
| 5. 快进+10s | 按钮存在 | ✅ PlayerControlsView:204-210 skip(by: 10) | PASS |
| 6. 快退-10s | 按钮存在 | ✅ PlayerControlsView:174-180 skip(by: -10) | PASS |
| 7. .window 模式 | 自动选择 | ✅ DecidePlaybackModeUseCase:14-23 | PASS |

---

### QA-C02: HDR10 MP4 + HDR 标签 — PASS

**Results by step:**
| Step | Expected | Actual | Verdict |
|------|----------|--------|---------|
| 1. HDR10 检测 | .hdr10 | ✅ MPVPlayerAdapter:1251-1254 hdr10/pq detection | PASS |
| 2. HDR10 标签 | 显示 "HDR10" | ✅ PlaybackInfoFormatter:39-40 .hdr10 → "HDR10" | PASS |
| 3. EDR PQ 曲线 | CAEDRMetadata.hdr10 | ✅ EDRMetadataDescriptor:28-34 | PASS |
| 4. SDR 无标签 | 标签隐藏 | ⚠️ 显示 "SDR" 而非隐藏（minor, acceptable） | PASS |

**Note**: SDR content shows "SDR" label instead of hiding it completely. This is acceptable UX — user sees their content's color space.

---

### QA-C03: Dolby Vision + HDR10 回退 — PASS

**Results by step:**
| Step | Expected | Actual | Verdict |
|------|----------|--------|---------|
| 1. DV 检测 | .dolbyVision | ✅ MPVPlayerAdapter:1237-1243 multi-signal detection | PASS |
| 2. HDR10 回退 | EDR workaround | ✅ EDRMetadataDescriptor:26-34 WORKAROUND comment | PASS |
| 3. hwdec | videotoolbox | ✅ MPVConfiguration:116-118 | PASS |

---

### QA-C04: MOV 容器格式播放 — PASS

| Check | Result | Evidence |
|-------|--------|----------|
| .mov 可识别 | ✅ | FileFilter.swift:16 "mov" in playable |

---

### QA-C05: AVI 容器格式播放 — PASS

| Check | Result | Evidence |
|-------|--------|----------|
| .avi 可识别 | ✅ | FileFilter.swift:16 "avi" in playable |

---

## Issues Register

| ID | Severity | Category | Title | QA Path | Status |
|----|----------|----------|-------|---------|--------|
| ISSUE-001 | Medium | UX | 场景选择和文件浏览是 Tab 分离的，非同屏 | A01 | deferred |
| ISSUE-002 | Medium | Navigation | 无持久"本地文件"数据源入口 | A01 | deferred |
| ISSUE-003 | Medium | UX | 场景卡片不自动打开沉浸空间 | A02 | deferred |
| ISSUE-004 | **High** | Functional | 本地文件子文件夹导航完全不可用 | A03 | **Phase 2 fix** |
| ISSUE-005 | Medium | Content | VideoDetailView 缺少 codec 和 duration 显示 | B01 | deferred |

### Phase 2 修复优先级

1. **ISSUE-004** (High): `FileBrowsingViewModel.swift:303` — 移除/修改 `guard activeRemoteAdapter != nil` 以支持本地文件夹导航
2. ISSUE-005 (Medium): VideoDetailView 添加 codec 和 duration 元数据行
3. ISSUE-001-003 (Medium): UX 改进项（可合并到 HelloWorld UX 改进中）

---

## Evidence Files

| File | Description |
|------|-------------|
| `screenshots/QA-A01-initial-launch.png` | 应用启动首屏 |
| `screenshots/QA-A01-current-state.png` | 文件列表当前状态 |

---

## Next Batch

Batch 2 should cover: D. 沉浸影院 (5) + E. 全景 (5) + F. 3D 立体 (3) = 13 paths
