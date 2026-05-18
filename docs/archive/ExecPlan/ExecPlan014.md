# ExecPlan014 — T0.5 测试代码落地

> Round: 5
> Phase: PLANNING
> 日期: 2026-04-02
> 目标: 将 EP012 测试计划转为 Swift 代码。创建 9 个 stub 源文件 + 8 个测试文件（43 tests），确认 old 205 PASS + new 43 FAIL

## 步骤

1. 创建 9 个 stub 源文件（SpatialSceneDomain namespace + 域类型）
2. 更新 Package.swift 添加所有新源文件 + 已有但未列入的依赖文件
3. 创建 8 个测试文件（43 tests）
4. `swift test` 确认编译通过 + 旧测试全 PASS + 新测试全 FAIL
5. git commit

## Stub 设计决策

- 所有新类型放在正确的域目录下（与最终位置一致）
- Stub 实现故意返回错误值（零值/nil/空字符串），确保每个测试 FAIL
- 每个测试至少验证一个 stub 返回错误的属性，避免纯结构测试 PASS
- CinemaEnvironment 增加 `displayName` 属性（stub 返回空字符串），用于拦截纯枚举结构测试
- VirtualScreenConfiguration 的 `default` 使用 (0,0) 尺寸，aspectRatio 返回 0
- StereoMode 的 UV rect 和 outputDimensions 返回零值
- DecidePlaybackModeUseCase 总是返回 .window

## 新增 Package.swift 源文件

### 新建 stub
- XrPlayer/SpatialScene/Domain/SpatialSceneDomain.swift
- XrPlayer/SpatialScene/Domain/CinemaEnvironment.swift
- XrPlayer/SpatialScene/Domain/ScreenGeometry.swift
- XrPlayer/SpatialScene/Domain/VirtualScreenConfiguration.swift
- XrPlayer/SpatialScene/Domain/HemisphereMeshConfiguration.swift
- XrPlayer/SpatialScene/Domain/FisheyeRemapConfiguration.swift
- XrPlayer/PlaybackCore/Domain/ValueObjects/StereoMode.swift
- XrPlayer/PlayerUI/Domain/Ports/PlaybackModeManaging.swift
- XrPlayer/PlayerUI/UseCases/DecidePlaybackModeUseCase.swift

### 已有但需加入 Package.swift
- XrPlayer/Persistence/Domain/ValueObjects/FileIdentifier.swift (PersistenceDomain namespace)
- XrPlayer/Persistence/Domain/Entities/SavedScreenPosition.swift
- XrPlayer/PlayerUI/Domain/ValueObjects/PlaybackMode.swift
