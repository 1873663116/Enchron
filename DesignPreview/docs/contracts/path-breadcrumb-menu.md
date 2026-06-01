# 组件契约:`PathBreadcrumbMenu`(路径面包屑菜单)

> 状态:已定稿(契约层)。未实现。

## 0. 角色
显示当前文件夹路径,点开是一个可跳转到任意上级层级的菜单。

## 1. 构造
显示当前文件夹名 + 一个列出各级祖先的菜单;点某级触发 `onSelectLevel(index)`。

## 2. 变体
无。

## 3. 暴露参数
| 参数 | 能调什么 | 影响 | 证据 |
|---|---|---|---|
| `path`(`[String]`) | 路径层级数组 | 显示什么路径、菜单有哪些级 | live/橱窗都传 |
| `onSelectLevel` | 选中某级回调 | 点某级的跳转行为 | 可变 |

## 4. 无障碍(硬要求)
- `accessibilityIdentifier` + `accessibilityLabel`(朗读当前路径);各级菜单项可被定位。

## 5. 锁死
玻璃、菜单 chrome、字体、所有相关 token——全锁。

## 6. 决策记录
1. 暴露面就 `path` + `onSelectLevel`,干净,无争议。
