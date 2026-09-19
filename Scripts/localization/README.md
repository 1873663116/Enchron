# 本地化

`Apps/Enchron/Resources/Localizable.xcstrings` 保存全部界面文案的译文，`InfoPlist.xcstrings` 保存三条系统权限说明与包名。模块代码（`Modules/`）查表时走 `Bundle.main`，所以表只有一份，放在 App 本体里。

## 用户怎么换语言

走系统的 per-app language：**设置 → Apps → Enchron → 语言**。这与系统语言相互独立，用户在系统设置里单独给 Enchron 选一种语言。

这是 Apple 唯一支持的路径。WWDC 2019/403 的原话：

> "do not attempt to set the application language manually in code. Our APIs do a lot of work to ensure users get the right language and font fallbacks."
>
> "If you do need to add the option within your app to switch languages, we recommend you launch into Settings where users can go and switch the language of your app."
>
> "When the user does change the language of your app, your app will be relaunched in the target language."

**没有运行时切换语言的 API。** 语言变更由系统在重启后生效，`Bundle` 的本地化在进程启动时确定，之后无法更改。任何"应用内即时切换"的实现都要绕开这条，代价是切换必然不完整——视图当场算出的文字会变，存进模型的字符串和别的窗口不会，因为没有任何机制通知它们。

因此本仓库不自己实现语言选择器。设置页那一行只提供一个跳转入口，用 `UIApplication.openSettingsURLString` 打开本应用的系统设置页。

`Config/Enchron-Info.plist` 里的 `UIPrefersShowingLanguageSettings` 让语言选项在用户只配置了一种语言时也显示；不声明的话，系统只在用户配置了多于一种语言时才显示它。

重启导致的体验中断用状态恢复抹平，Apple 的建议是 iOS 13 起的 `NSUserActivity` 状态恢复 API。

## 重建表

```bash
python3 Scripts/localization/extract_strings.py
```

脚本带 `SWIFT_EMIT_LOC_STRINGS=YES` 跑一次 `xcodebuild`，再从 `.scratch/derived-data` 收编译器为每个源文件产出的 `.stringsdata`，过滤后合并进表。已有译文保留，新键加进去，不再出现的键标成 `stale`（`--prune` 改为删除）。

编译器为 DerivedData 下的生成源同样产出 stringsdata，其中带着 `InfoPlist` 的键；那些键属于 `InfoPlist.xcstrings`，脚本按来源前缀剔除。

`--check` 不写文件，表与源码不一致时退出码为 1，可挂进 CI。

## 为什么不用 Xcode 自带的导出

Xcode 的自动抽取只覆盖设置了 `SWIFT_EMIT_LOC_STRINGS` 的 target，工程里只有 App target 开了；`Modules/` 下的五个 SPM 包需要命令行传这个设置才会产出（脚本已传）。

`xcstringstool extract` 可用但不够：它把所有插值记成 `%arg`，而 `%arg` 不是合法的格式符，构建的符号生成阶段会直接报错；它也不理解传给自定义组件参数的字面量。编译器产出的键是类型正确的（`%lld`、`%@`），且能认出传给 `LocalizedStringKey` 参数的字面量。

## 文案怎么写才进表

**视图里的字面量直接写**，SwiftUI 的 `Text`、`Label`、`Button`、`.navigationTitle`、`.accessibilityLabel` 都会把它当本地化键：

```swift
Text("Cancel")
Button("Resume") { … }
.accessibilityLabel("Back")
```

**取值发生在视图之外时用 `String(localized:)`**。模型、视图模型、计算属性里算出来存进结构的字符串不会随后续渲染更新，所以要么在那里用 `String(localized:)` 当场解析，要么把键存下来、在视图里解析：

```swift
SidebarSourceItem(title: String(localized: "Media Library"))
```

数据值（影片名、服务器名）不要包——`String(localized:)` 只在表里存在对应键时才替换，包上也不会被改写，但会平白多一次查表。

## 翻译

表是唯一真相源，译文只经由脚本进出：

```bash
python3 Scripts/localization/translations.py export --language ja --output work.json
# 翻译 work.json，产出 {"language": "ja", "translations": {…}}
python3 Scripts/localization/translations.py import --language ja --input translated.json
python3 Scripts/localization/translations.py status
python3 Scripts/localization/locale_coverage.py --app <built .app>
```

`glossary.md` 是译员必须遵守的术语与标点约束，含义取自 `docs/CONTEXT.md`。

**不要用 `xcodebuild -exportLocalizations`。** 它按 target 重新抽取并重写 catalog，而只有 App target 设置了 `SWIFT_EMIT_LOC_STRINGS`，所以它会把模块来源的键全部丢掉——实测把表从 216 键砍到 55 键。`--importLocalizations` 同理，不要走 Xcode 的导入导出。

`locale_coverage.py` 断言三件事：每种在表里的语言没有漏译、每条译文的占位符与原文一致、每种语言的译文确实编进了 App 包。这些问题在运行时都静默——表现为某一句或整个语言还是英文。

## 规则

`rules.json` 两项：

- `excludedKeys`：开发者诊断界面和纯数值常量，这些键不出现在表里。
- `excludedFiles`：整个文件排除。

`#Preview` 块内的文案和去掉格式符后不含字母的键，脚本自动排除。

## 已知边界

- 复数：`%lld items`、`%lld selected` 在法语、德语、俄语按各自的复数规则写 variations；俄语需要 one/few/many/other 四档。编译后复数键落进 `stringsdict` 而不是 `strings` 表，`locale_coverage.py` 比对前把两者合并。
- 表按源码原文作键，一处英文改动等于新增一个键，已有译文需要重新绑定。
- 视图之外产生的字符串如果忘了 `String(localized:)`，不会被抽到，也没有检查能发现。
