---
name: flutter-mcp-testing
description: |
  Flutter 四工具联合测试：Marionette MCP（16 tools）+ Dart MCP（25 tools）+ Mobile MCP（21 tools）+ Codex CLI。
  Marionette tap by text、热重载循环、widget tree 检查、录屏、截图存档、多语言测试。
  触发关键字：marionette、mcp 测试、热重载、flutter driver、widget tree、录屏、截图对比
---

## 核心定位

三个 MCP 工具各管一层，组合覆盖 Flutter 开发全流程：

```
Dart MCP (25 tools)     — 代码层：分析、热重载、测试、widget 检查、driver 自动化
Mobile MCP (21 tools)   — 设备层：截图、录屏、原生 UI 操作、安装、启动
Codex CLI               — 审查层：只读代码审查、独立安全分析
```

## 一、Dart MCP 完整工具清单（25 个）

### 代码分析（4 个）

| 工具 | 用途 | 参数 |
|------|------|------|
| `analyze_files` | 静态分析 | `roots[].root`(file URI), `roots[].paths[]` |
| `hover` | 光标悬停信息（类型、文档） | `uri`, `line`(0-based), `column`(0-based) |
| `signature_help` | 函数签名帮助 | `uri`, `line`, `column` |
| `resolve_workspace_symbol` | 模糊搜索符号 | `query`(大小写不敏感) |

### 应用生命周期（5 个）

| 工具 | 用途 | 参数 |
|------|------|------|
| `launch_app` | 启动 Flutter 应用 | `root`, `device`, `target`(默认 lib/main.dart) |
| `list_devices` | 列出可用设备 | 无 |
| `list_running_apps` | 列出运行中的应用 | 无 |
| `stop_app` | 终止应用 | `pid` |
| `get_app_logs` | 获取日志 | `pid`, `maxLines`(默认 500, -1=全部) |

### 热更新 + 调试（4 个，需先 connect）

| 工具 | 用途 | 参数 |
|------|------|------|
| `connect_dart_tooling_daemon` | 连接运行中的应用 | `uri`(DTD URI, 从 launch_app 返回) |
| `hot_reload` | 热重载（保持状态） | `clearRuntimeErrors`(bool) |
| `hot_restart` | 热重启（重置状态，更新 const） | 无 |
| `get_runtime_errors` | 获取运行时错误 | `clearRuntimeErrors`(bool) |

### Widget 检查（4 个，需先 connect）

| 工具 | 用途 | 参数 |
|------|------|------|
| `get_widget_tree` | 获取 widget 树 | `summaryOnly`(true=仅用户代码 widget) |
| `get_selected_widget` | 获取选中 widget 详情 | 无 |
| `set_widget_selection_mode` | 开关 widget 选择模式 | `enabled`(bool) |
| `get_active_location` | 获取编辑器光标位置 | 无 |

### Flutter Driver 自动化（1 个工具，多命令）

| 命令 | 用途 |
|------|------|
| `tap` | 点击 widget |
| `enter_text` | 输入文本 |
| `get_text` | 获取 widget 文本 |
| `scroll` | 滚动（dx/dy/duration/frequency） |
| `scrollIntoView` | 滚动至 widget 可见 |
| `send_text_input_action` | 发送输入法动作（done/go/search/send/next） |
| `set_text_entry_emulation` | 设置文本输入模拟 |
| `waitFor` | 等待 widget 出现 |
| `waitForAbsent` | 等待 widget 消失 |
| `waitForTappable` | 等待 widget 可点击 |
| `get_offset` | 获取 widget 位置 |
| `screenshot` | 截图 |
| `get_health` | 检查应用健康 |
| `get_diagnostics_tree` | 获取诊断树 |

**Finder 类型**：`ByType` / `ByValueKey` / `ByText` / `BySemanticsLabel` / `ByTooltipMessage` / `PageBack` / `Descendant` / `Ancestor`

### 项目创建（1 个，默认禁用）

| 工具 | 用途 | 参数 |
|------|------|------|
| `create_project` | 创建新 Dart/Flutter 项目 | `directory`, `projectType`(dart/flutter), `root`(file URI), `template`, `platform[]` |

### 包管理 + 测试（6 个）

| 工具 | 用途 |
|------|------|
| `pub` | add/remove/get/deps/outdated/upgrade |
| `pub_dev_search` | 搜索 pub.dev（支持 `topic:` `sdk:` `dependency:` 等） |
| `read_package_uris` | 读取包文件内容 |
| `dart_fix` | 自动修复代码问题 |
| `dart_format` | 格式化代码 |
| `run_tests` | 跑测试（支持 fail-fast/coverage/shard/tags） |

---

## 二、Mobile MCP 完整工具清单（21 个）

### 设备管理（6 个）

| 工具 | 用途 |
|------|------|
| `mobile_list_available_devices` | 列出所有设备/模拟器 |
| `mobile_list_apps` | 列出已安装 app |
| `mobile_launch_app` | 启动 app（**支持 locale 参数**） |
| `mobile_terminate_app` | 关闭 app |
| `mobile_install_app` | 安装 apk/ipa/app |
| `mobile_uninstall_app` | 卸载 app |

### 屏幕信息（3 个）

| 工具 | 用途 | 参数 |
|------|------|------|
| `mobile_get_screen_size` | 屏幕尺寸 | `device`(必填) |
| `mobile_get_orientation` | 获取横竖屏 | `device`(必填) |
| `mobile_set_orientation` | 设置横竖屏 | `device`(必填), `orientation`("portrait"/"landscape") |

### 截图录屏（4 个）

| 工具 | 用途 |
|------|------|
| `mobile_take_screenshot` | 截图返回图片（给 LLM 看） |
| `mobile_save_screenshot` | 截图存文件（`saveTo` 必须 .png/.jpg） |
| `mobile_start_screen_recording` | 开始录屏 MP4 |
| `mobile_stop_screen_recording` | 停止录屏，返回文件路径 |

### UI 操作（8 个）

| 工具 | 用途 |
|------|------|
| `mobile_list_elements_on_screen` | 获取无障碍树（坐标、标签） |
| `mobile_click_on_screen_at_coordinates` | 单击 |
| `mobile_double_tap_on_screen` | 双击 |
| `mobile_long_press_on_screen_at_coordinates` | 长按（duration 可设 1-10000ms） |
| `mobile_swipe_on_screen` | 滑动（方向+距离+起点） |
| `mobile_type_keys` | 输入文字（submit 可按回车） |
| `mobile_press_button` | 硬件键（HOME/BACK/VOLUME） |
| `mobile_open_url` | 打开 URL（需 `MOBILEMCP_ALLOW_UNSAFE_URLS=1` 才支持 deep link） |

---

## 二点五、Mobile MCP 操作 Flutter 的可靠性规则

> **来源**：2026-04-15 实测，Mobile MCP 坐标点击 Flutter UI 平均 3 次才命中。

Flutter 自己渲染 UI，平台无障碍树只有粗略区域，坐标经常偏。遵循以下规则提升成功率：

### 规则 1：永远先 list_elements，不要猜坐标
```
错误：截图 → 目测"大概在这" → click(240, 550)
正确：list_elements_on_screen → 找到元素 → click(x + width/2, y + height/2)
```

### 规则 2：文字输入用 adb/xcrun，不用 type_keys
```
Android: adb -s {device} shell input text "91234567"
iOS sim: xcrun simctl keyboardInput {device_id} 91234567
```
`type_keys` 依赖焦点状态，Flutter 经常吃不到。adb input 直接注入到系统层，100% 可靠。

### 规则 3：等元素出现后再操作
```
操作前先 take_screenshot 确认页面状态
弹窗/页面切换后等 1-2 秒再 list_elements
不要连续快速操作
```

### 规则 4：有 Marionette 就用 Marionette
Marionette MCP 的 `tap("文字")` 直接在 Flutter 层操作，不走坐标，一次命中。
配好后优先用 Marionette，Mobile MCP 只用于原生弹窗和截图。

> **配置状态**：MCP server `marionette_mcp 0.5.0` 已全局安装 + 已配在 `.claude.json`。
> App 端 `marionette_flutter` 主仓库是 0.4.0（不推到 dev），**worktree 里需手动升到 ^0.5.0**：
> `sed -i '' 's/marionette_flutter: ^0.4.0/marionette_flutter: ^0.5.0/' pubspec.yaml && flutter pub get`
> 不升的话连接会报 version mismatch。每次新 worktree 记得做这步。

### Marionette MCP 工具清单（16 个）

| 工具 | 用途 | 参数 |
|------|------|------|
| `connect` | 连接运行中的 Flutter app | VM service URI (`ws://127.0.0.1:xxxxx/ws`) |
| `disconnect` | 断开连接 | 无 |
| `get_interactive_elements` | 列出屏幕上所有可交互元素 | 无 |
| `tap` | 点击元素 | key 或可见文本 |
| `double_tap` | 双击元素 | key 或可见文本 |
| `long_press` | 长按元素 | key 或可见文本 |
| `enter_text` | 输入文字 | key（匹配目标字段） |
| `scroll_to` | 滚动到元素可见 | key 或可见文本 |
| `swipe` | 滑动 | 方向 + 距离 |
| `pinch_zoom` | 捏合缩放 | 缩放比例 |
| `press_back_button` | 按返回键 | 无 |
| `take_screenshots` | 截图（base64） | 无 |
| `hot_reload` | 热重载 | 无 |
| `get_logs` | 获取日志 | 需 app 端配 LogCollector |
| `list_custom_extensions` | 列出自定义 VM extension | 无 |
| `call_custom_extension` | 调用自定义 extension | extension 名 + 参数 |

## 三、工具选择决策树

```
需要操作 Flutter widget？
├── Marionette 已连接 → tap("文字") / enter_text（最可靠，一次命中）
├── 知道 widget 类型/Key → flutter_driver ByType/ByValueKey（精确）
├── 只知道屏幕坐标 → Mobile MCP click（先 list_elements 取精确坐标）
└── 原生系统弹窗/权限框 → Mobile MCP（Marionette/flutter_driver 看不到原生 UI）

需要检查 UI 结构？
├── Flutter widget 树 → Dart MCP get_widget_tree
└── 平台无障碍树 → Mobile MCP list_elements_on_screen

需要截图？
├── 给 LLM 看 → Mobile MCP take_screenshot
├── 存文件附 PR → Mobile MCP save_screenshot
└── Flutter 渲染级截图 → flutter_driver screenshot

需要录屏？
└── Mobile MCP start/stop_screen_recording（唯一选择）
```

---

## 四、常用工作流

### 工作流 1：Hot Reload 快速迭代

```
1. mcp__dart__list_devices()
2. mcp__dart__launch_app(root, device, target)    → 获取 DTD URI
3. mcp__dart__connect_dart_tooling_daemon(uri)
4. 循环：
   a. 编辑代码
   b. mcp__dart__hot_reload(clearRuntimeErrors: true)
   c. mcp__dart__get_runtime_errors()
   d. 有错误 → 修复 → 回到 a
   e. 无错误 → 继续下一个改动
5. 需要更新 const → mcp__dart__hot_restart()
```

### 工作流 2：设备全流程测试 + 录屏

```
1. mcp__mobile-mcp__mobile_start_screen_recording(device)
2. mcp__dart__flutter_driver(command: "tap", finderType: "ByText", text: "登录")
3. mcp__dart__flutter_driver(command: "enter_text", text: "91234567")
4. mcp__dart__flutter_driver(command: "waitFor", finderType: "ByType", type: "OtpPage")
5. mcp__mobile-mcp__mobile_save_screenshot(device, saveTo: "/tmp/login_otp.png")
6. mcp__mobile-mcp__mobile_stop_screen_recording(device) → MP4 文件
```

### 工作流 3：Widget 调试

```
1. mcp__dart__get_widget_tree(summaryOnly: true)  → 确认结构
2. mcp__dart__get_runtime_errors()                  → 找 overflow 等
3. 有问题时：
   mcp__dart__set_widget_selection_mode(enabled: true)
   → 在设备上点选有问题的 widget
   mcp__dart__get_selected_widget()                → 获取 constraints/size/render 详情
   mcp__dart__set_widget_selection_mode(enabled: false)
```

### 工作流 4：Codex 只读审查

```bash
codex exec \
  -s read-only \
  -c 'mcp_servers={}' \
  --ephemeral \
  -C <worktree路径> \
  "Review git diff dev..HEAD. Flutter MVVM + Riverpod.
   Focus: architecture, logic bugs, security, dead code.
   Output: Critical/High/Medium/Low with file:line."
```

注意：
- `-C` 必须指向 **worktree 路径**，不能用主仓库路径（否则读错分支代码）
- `-c 'mcp_servers={}'` 禁用所有 MCP（避免 Figma 卡死）

---

## 四点五、Golden Test 互补（CI 自动回归）

四工具（Marionette + Dart MCP + Mobile MCP + Codex）覆盖**开发阶段**的实时验证，Golden Test 覆盖 **CI 阶段**的自动回归：

| 层级 | 工具 | 触发时机 |
|------|------|---------|
| 开发实时 | Marionette tap + Dart MCP widget tree + Mobile MCP 截图 | 每次 hot_reload 后 |
| CI 回归 | Golden Test（alchemist / golden_test） | 每次 PR push |
| Figma 对比 | ImageMagick SSIM（verify-ui-auto skill） | UI 功能完成时 |

**推荐包**：
- **[alchemist](https://pub.dev/packages/alchemist)** 0.14.0 — 双 golden 系统（CI golden 跨平台一致 + 平台 golden 人可读），成熟稳定，默认推荐
- **[golden_test](https://pub.dev/packages/golden_test)** 1.0.1 — 轻量级，内建多设备 + 多语言 + 容差，适合新项目尝鲜
- ~~golden_toolkit~~ 0.15.0 — 已标记 discontinued，存量项目可继续用，不建议新接入

**跨平台要点**：
- Widget golden test 跑在 Flutter test harness（无头渲染），不是模拟器/真机
- macOS vs Linux 渲染差异（字体引擎、阴影、文字抗锯齿等）→ 用 Alchemist 双 golden 或 macOS CI runner
- Flutter 版本升级（尤其 3.27+ Impeller 默认化）后 golden 可能需要更新
- 容差推荐：`0.0002`（= 0.02%，M1 vs x86），`>0.01`（>1%）太高会漏 bug

详见 skill: `verify-ui-auto`

---

## 五、Flutter 特别注意

1. **flutter_driver 命令需要 `enableFlutterDriverExtension()`** — tap/screenshot/waitFor 等命令需要 app 端调用此函数。当前项目未启用，因此日常开发中 flutter_driver UI 操作不可用。仅 `get_widget_tree`（87KB，iOS 模拟器实测）和 `get_runtime_errors` 等诊断工具可通过 DTD 连接直接使用，不需要 extension。
2. **Flutter widget 不自动出现在平台无障碍树** — Material 组件（TextField/Button 等）自带 Semantics，自定义 widget 需手动加 `Semantics` wrapper
2. **flutter_driver vs Mobile MCP**：
   - flutter_driver 通过 VM Service 直接操作 Flutter widget，精确但只能操作 Flutter UI
   - Mobile MCP 通过平台 accessibility API 操作，能操作原生 UI 但看不到无 Semantics 的 Flutter widget
3. **Dart MCP 需要 Dart SDK >= 3.9**，启动命令：`dart mcp-server --force-roots-fallback`

---

## 六、环境变量

| 变量 | 作用 |
|------|------|
| `MOBILEMCP_ALLOW_UNSAFE_URLS=1` | 允许 deep link scheme（myapp://） |
| `MOBILEMCP_DISABLE_TELEMETRY=1` | 禁用匿名遥测 |
| `MOBILEFLEET_ENABLE=1` | 启用远程设备池 |

## 七、dev-team Phase 对应

| Phase | Marionette MCP | Dart MCP | Mobile MCP | Codex |
|-------|---------------|----------|------------|-------|
| 1 探索 | — | analyze_files, resolve_workspace_symbol, hover | — | — |
| 2 编码 | — | **hot_reload 循环**, run_tests, dart_format | — | — |
| 3 集成 | — | run_tests(fail-fast), analyze_files | save_screenshot 对比 | — |
| 4 真机 | **tap/enter_text（首选）** | flutter_driver, get_widget_tree, get_runtime_errors | **录屏**, save_screenshot, launch_app(locale) | — |
| 4.8 回归 | — | — (Golden Test via flutter test) | — | — |
| 5 审查 | — | — | — | **exec read-only** |
| 6 监控 | — | — | — | exec review |
