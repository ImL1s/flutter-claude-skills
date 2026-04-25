---
name: verify-ui-auto
description: |
  Automated UI verification loop: Marionette screenshot -> Figma reference -> pixel-diff -> difference list -> auto-fix iteration. Solves the false-positive verification problem flagged in insights reports (UI claimed fixed without actually being compared against the reference).
  Triggers (English): verify ui, ui compare, pixel diff, figma compare, automated ui verification, golden test fail.
  自动 UI 验证：Marionette 截图 → Figma 参考图 → pixel-diff → 差异列表 → 自动修复循环。
  触发关键字（中文）：verify ui、ui 对比、pixel diff、figma 对比、自动验证
last-verified-against: Flutter 3.27 (2026-Q1)
---

## 核心流程

```
1. Figma MCP 截取参考图（get_design_context / get_screenshot）
2. Marionette/Mobile MCP 截取当前 app 图
3. 像素对比（dart CLI 工具 or ImageMagick compare）
4. diff > 阈值 → 列出差异区域 → 修改代码 → hot_reload → 重新截图 → 循环
5. diff < 阈值 → PASS，输出证据
```

## 工具选择

| 步骤 | 工具 | 备注 |
|------|------|------|
| Figma 参考图 | `mcp__claude_ai_Figma__get_screenshot` | 需 fileKey + nodeId |
| App 截图 | `mcp__marionette__take_screenshots` 或 `mcp__mobile-mcp__mobile_save_screenshot` | Marionette 优先 |
| 像素对比 | `compare` (ImageMagick) 或 Dart `image` 包 | 输出 diff 百分比 + diff 图 |
| 修改后重验 | `mcp__dart__hot_reload` → 重新截图 → 重新对比 | 循环直到通过 |

## 方法 A：Flutter Golden Tests（推荐，CI 内建）

Flutter 内建截图回归测试，不需要外部工具。

### 核心原理

`matchesGoldenFile()` 将 widget 渲染为 PNG，与参考图做比对：**先 PNG 原始字节快速比对（`listEquals`），不一致时再解码为 RGBA 逐像素差异计算**。默认 `LocalFileComparator` **零容差**——一个像素不同即 fail。

⚠️ **关键认知：Widget golden test（`flutter test`）不跑在模拟器/真机上**，而是跑在 Flutter test harness（无头渲染）。所以「模拟器渲染差异」**不直接影响** widget golden，但 macOS vs Linux **渲染差异**（字体引擎 CoreText vs FreeType、阴影渲染、文字抗锯齿等）会导致跨平台不一致。注：`integration_test` 有 `VmServiceProxyGoldenFileComparator` 可做设备侧截图+主机侧比对，不在此讨论范围。

### 基础用法

```dart
// test/golden/login_page_golden_test.dart
testWidgets('login page matches golden', (tester) async {
  // 固定设备参数，避免环境差异
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = Size(1170, 2532); // iPhone 14 Pro
  await tester.pumpWidget(MaterialApp(home: LoginPage()));
  await expectLater(
    find.byType(LoginPage),
    matchesGoldenFile('goldens/login_page.png'),
  );
});
```

```bash
# 首次生成参考图
flutter test --update-goldens test/golden/

# 之后每次 CI 自动对比
flutter test test/golden/
# 有差异 → 测试失败 + 生成 isolatedDiff.png / maskedDiff.png
```

### 容差配置（解决跨平台问题）

```dart
// test/flutter_test_config.dart（放 test/ 根目录，自动对所有测试生效）
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 自定义容差比较器（基于 Flutter SDK goldens.dart 官方模式）
/// 注意：必须调用 result.dispose() 释放 GPU 内存，失败时 throw FlutterError 输出 diff 图路径
class LocalFileComparatorWithThreshold extends LocalFileComparator {
  final double threshold; // 0.0002 = 0.02%

  LocalFileComparatorWithThreshold(super.testFile, {required this.threshold});

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final ComparisonResult result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    final bool passed = result.passed || result.diffPercent <= threshold;
    if (passed) {
      result.dispose();
      return true;
    }
    // 失败时生成 diff 图 + 详细错误信息，然后释放资源
    final String error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 加载真实字体（避免 Ahem 方块）
  final fontData = rootBundle.load('assets/fonts/Roboto-Regular.ttf');
  final fontLoader = ui.FontLoader('Roboto')..addFont(fontData);
  await fontLoader.load();

  // 设置容差：0.02% 足够覆盖 M1 vs x86 差异，但不会漏掉真正的 UI bug
  goldenFileComparator = LocalFileComparatorWithThreshold(
    Uri.parse('test/flutter_test_config.dart'),
    threshold: 0.0002, // Rows 工程实践：0.02%
  );

  await testMain();
}
```

**容差选择经验**（⚠️ 阈值为 0..1 小数比值，不是百分比！`0.0002` = 0.02%，`0.02` = 2%，常见混淆点）：
| 阈值代码值 | 等效百分比 | 场景 | 来源 |
|-----------|-----------|------|------|
| 0（默认） | 0% | 同平台同架构 CI | Flutter 默认 |
| 0.0002 | 0.02% | M1 vs x86 / 微小字体差异 | Rows 工程团队实践 |
| 0.005 | 0.5% | 跨 OS（macOS ↔ Linux）| 社区常用上限 |
| >0.01 | >1% | ❌ 太高，会漏掉真正的 bug | 不推荐 |

### 跨平台解决方案（macOS vs Linux = #1 痛点）

**方案 1：CI 用 macOS runner（推荐，匹配开发机）**
```yaml
# .gitea/workflows/golden.yml
jobs:
  golden_tests:
    runs-on: macos-latest  # 匹配开发者 Mac
    steps:
      - uses: subosito/flutter-action@v2
      - run: flutter test --tags=golden
  
  unit_tests:
    runs-on: ubuntu-latest  # 逻辑测试用 Linux，便宜快
    steps:
      - uses: subosito/flutter-action@v2
      - run: flutter test --exclude-tags=golden
```

**方案 2：Docker 统一环境**
```bash
# 在 CI 用的同一个 Docker 镜像里生成参考图
docker run --rm -v $(pwd):/app -w /app ghcr.io/cirruslabs/flutter:stable \
  flutter test --update-goldens --tags=golden
```

**方案 3：Alchemist 双 golden 系统（最优雅）**
- **平台 golden**：真实字体渲染，人可读，不入 git（平台相关）
- **CI golden**：文字替换为色块（Ahem 字体），入 git，跨平台一致

### 推荐工具

| 工具 | 状态 | 特点 |
|------|------|------|
| **[alchemist](https://pub.dev/packages/alchemist)** 0.14.0 | ✅ 活跃维护（Betterment） | 双 golden 系统（CI/平台分离），成熟稳定，默认推荐 |
| **[golden_test](https://pub.dev/packages/golden_test)** 1.0.1 | ✅ 全新（2026-04） | 轻量级，内建多设备+多语言+容差，适合新项目尝鲜 |
| **[Widgetbook Cloud](https://www.widgetbook.io/cloud)** | ✅ SaaS | 云端渲染，零配置跨平台，PR 审查门禁 |
| ~~golden_toolkit~~ 0.15.0 | ⚠️ 已标记 discontinued | 存量项目可继续用，不建议新项目接入 |

### Alchemist 集成示例

```dart
// test/flutter_test_config.dart
// ⚠️ 以下基于 alchemist 0.14.0（2026-04 确认），使用前先 pub.dev 确认最新 API
import 'package:alchemist/alchemist.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  const isCI = bool.fromEnvironment('CI', defaultValue: false);
  return AlchemistConfig.runWithConfig(
    config: AlchemistConfig(
      theme: ThemeData.light(),
      platformGoldensConfig: PlatformGoldensConfig(enabled: !isCI),
    ),
    run: testMain,
  );
}
```

```gitignore
# .gitignore — 只跟踪 CI golden，不跟踪平台 golden
test/**/goldens/**/*.*
test/**/failures/**/*.*
!test/**/goldens/ci/*.*
```

### 多设备/多密度测试

```dart
// golden_test v1.0.1 内建设备配置
// ⚠️ 该包 2026-04 全新发布，API 可能变动，使用前先确认 pub.dev 文档
goldenTest(
  'my widget on multiple devices',
  widget: MyWidget(),
  supportedDevices: [
    Device.iphone15Pro(),     // 393×852 @3x
    Device.pixel9ProXL(),     // 411×924 @3.5x
    Device.ipadPro12(),       // 1024×1366 @2x
  ],
);
```

⚠️ **DPR 影响文件大小**：390×844 逻辑尺寸 × DPR 3.0 = 1170×2532 像素 golden。Retina 参考图比 1x 大 4-9 倍。

### Impeller 注意事项（Flutter 3.27+）

- Flutter 3.27 起 Impeller 成为 iOS + Android (API 29+) 默认渲染引擎
- 升级 Flutter 版本后 **golden 可能需要更新**（渲染引擎、字体、阴影等变化都可能影响像素输出）
- 已知问题：内容缩放 bug（PR #167308）、文字渲染偏差（issue #141467）

### 优势
精确到 widget 级别、跑在 CI 里、不需要真机/模拟器、Alchemist 解决跨平台问题。

## 方法 B：ImageMagick compare（真机截图对比）

```bash
# SSIM（结构相似度，更贴近人眼感知）
compare -metric SSIM reference.png current.png diff.png 2>&1
# 返回 0-1，1=完全相同

# 像素差异数
compare -metric AE reference.png current.png diff.png 2>&1
```

## 方法 C：flutter-skill（253 MCP 工具，跨 10 平台）

[ai-dashboard/flutter-skill](https://github.com/ai-dashboard/flutter-skill) 提供 AI 原生 E2E 测试：
- 用无障碍树而非截图，token 节省 87-99%
- click 只要 1-2ms（比 Playwright 快 50-100x）
- 自然语言写测试："测试空购物车结账流程"
- 支持 Flutter + React Native + iOS + Android + Web + Electron + Tauri + KMP
- 安装：`npx flutter-skill`
- 适合需要跨平台 E2E 的场景，比 Marionette 覆盖面更广

## 方法 D：Widgetbook Cloud（零配置跨平台）

[Widgetbook Cloud](https://www.widgetbook.io/cloud) 云端渲染解决方案：
- 自动为所有 widget 状态 × 设备 × 主题 × text scale 生成 golden
- 云端渲染，**彻底消除本地 vs CI 平台差异**
- PR 审查门禁：视觉变化必须人工审批才能合并
- 安装：`flutter pub add widgetbook_golden_test`
- 适合团队协作、设计师参与 review 的场景

## 阈值

### Golden Tests（方法 A）
| 容差 | 场景 | 判定 |
|------|------|------|
| 0% | 同平台同架构 | 严格通过/失败 |
| 0.02% | M1 vs x86 | 允许微小架构差异 |
| 0.5% | macOS vs Linux | 允许字体渲染差异 |
| >1% | ❌ | 会漏掉真正的 bug |

### ImageMagick SSIM（方法 B，真机 vs Figma）
| 级别 | SSIM | 像素差 | 判定 |
|------|------|--------|------|
| PASS | >= 0.95 | < 2% | 通过 |
| WARN | 0.90-0.95 | 2-5% | 需人工确认 |
| FAIL | < 0.90 | > 5% | 必须修 |

## 与 dev-team Phase 4 集成

### 开发阶段（真机/模拟器对比 Figma）
1. `get_screenshot(figma_url)` 取参考图存 `/tmp/ref_{page}.png`
2. `take_screenshots()` 或 `save_screenshot(device, saveTo)` 取当前图存 `/tmp/cur_{page}.png`
3. `compare -metric SSIM /tmp/ref_{page}.png /tmp/cur_{page}.png /tmp/diff_{page}.png`
4. SSIM < 0.95 → 看 diff 图 → 修改 → hot_reload → 重新对比
5. SSIM >= 0.95 → PASS，diff 图附到 PR

### CI 阶段（Golden Tests 自动回归）
1. 开发完成后 `flutter test --update-goldens` 生成参考图
2. 参考图入库（`test/golden/goldens/` 目录）
3. 每次 PR 的 CI 跑 `flutter test test/golden/`
4. 有视觉回归 → CI fail + 生成 diff 图 → 必须修

### Figma → Code → Verify 完整循环
参考 [BuildMVPFast](https://www.buildmvpfast.com/blog/figma-to-code-pixel-perfect-loop-ai-agent-screenshot-iterate-2026)：
```
Figma get_design_context → AI 生成/修改代码 → hot_reload → 截图
→ compare SSIM → 差异 > 5%？→ AI 分析 diff 图找出差异区域
→ 修改对应 widget → hot_reload → 重新截图 → 直到 SSIM >= 0.95
```
这个循环可以完全自动化，AI 不需要人工介入就能收敛到 pixel-perfect。

## 社区痛点 & 解决方案总结

| 痛点 | 解决方案 | 工具 |
|------|---------|------|
| macOS vs Linux 字体渲染 | 双 golden 系统 | Alchemist |
| 默认测试字体（FlutterTest, v3.7+）不够清晰 | 加载真实字体 | `FontLoader` in `flutter_test_config.dart` |
| Flutter 版本升级可能破坏 golden | 锁定版本 + 升级时检查 golden | CI 版本固定 |
| golden_toolkit 已 discontinued | 新项目用 alchemist 或 golden_test | 活跃维护的包 |
| 动态内容（网络图片、时间） | Mock 网络图片、冻结时间 | `network_image_mock`、`clock` 包 |
| 不同屏幕密度 | 固定 DPR + 多设备矩阵 | golden_test `Device.*()` |

## 前置条件

- ImageMagick 已安装：`brew install imagemagick`
- Figma MCP 可用：`.claude.json` 已配 figma server
- Marionette MCP 已连接（或 Mobile MCP 可用）
- Golden test 推荐包：`flutter pub add --dev alchemist` 或 `flutter pub add --dev golden_test`
- 开发阶段实时验证工具见 skill: `flutter-mcp-testing`

## 限制

- Figma 截图和 app 截图分辨率/DPI 可能不同，需先 resize 到同尺寸
- 状态栏/导航栏区域应裁剪排除（时间、电量等动态内容）
- 动画/loading 状态需等稳定后再截图
- **Golden test 跨平台限制**：macOS 生成的参考图在 Linux CI 上会 fail（字体渲染差异），必须用统一环境或 Alchemist 双 golden
- **渲染引擎/版本变更**：Flutter 3.27+ 默认 Impeller，升级 SDK 后 golden 可能需要更新（渲染引擎、字体、阴影等都可能变化）
- **DPR 影响文件大小**：高 DPR 设备的 golden 文件显著更大（3x DPR = 9 倍像素数）

## Related skills

- **`verify-ui`** — **DISAMBIGUATION**: verify-ui is manual screenshot comparison and iteration. verify-ui-auto is automated golden-file visual regression testing. Use verify-ui first for initial implementation verification; then use verify-ui-auto for CI-based regression prevention.
- **`visual-verdict`** — use alongside verify-ui to quantify diffs before setting up verify-ui-auto golden tests.
- **`figma-implement-design`** — after implementing a Figma design, use verify-ui for manual comparison, then verify-ui-auto to set up automated visual testing.
