---
name: flutter-verify
description: 改完代碼後的多層驗證流程。靜態分析 + 跑測試 + widget tree 檢查 + runtime error 檢測。觸發詞：verify、驗證、確認改動
---

# Flutter 多層驗證

改完代碼後執行此流程，按層依序驗證，任何一層失敗即停止修復。

## 流程

### Layer 0：靜態分析（必跑，無需設備）

用 `mcp__dart__analyze_files` 分析本次改動的文件：

```
analyze_files(roots: [{
  root: "file:///path/to/your/flutter/project",
  paths: [改動的文件列表]
}])
```

**失敗處理**：修復所有 error，重跑直到 "No errors"。

### Layer 1：跑測試（必跑，無需設備）

用 `mcp__dart__run_tests` 跑相關測試：

```
run_tests(roots: [{
  root: "file:///path/to/your/flutter/project",
  paths: [相關測試文件]
}])
```

測試文件定位規則：
- `lib/features/X/...` → `test/features/X/...`
- `lib/core/X/...` → `test/core/X/...`
- `lib/data/X/...` → `test/data/X/...`
- 找不到對應測試文件 → 跳過，不報錯

**失敗處理**：讀取失敗訊息，修復代碼，重跑。

### Layer 2：Widget Tree 檢查（需要設備連接，選跑）

前提：app 已透過 `launch_app` 啟動且 `connect_dart_tooling_daemon` 已連接。

1. `get_runtime_errors(clearRuntimeErrors: true)` — 清除舊錯誤
2. `hot_restart` — 載入最新代碼
3. 等 3 秒讓 app 穩定
4. `get_runtime_errors()` — 檢查有無新 crash
5. `get_widget_tree(summaryOnly: true)` — 確認頁面結構正確

**失敗處理**：有 runtime error 則讀取錯誤訊息，修復代碼，回到 Layer 0。

### Layer 3：視覺驗證（需要設備，僅 UI 改動時）

用 Mobile MCP 截圖確認外觀：
- `mobile_take_screenshot` — 截圖
- 對比參考設計

## 判斷哪些 Layer 要跑

| 改動類型 | Layer 0 | Layer 1 | Layer 2 | Layer 3 |
|---------|---------|---------|---------|---------|
| 純邏輯（UseCase/ViewModel/Repository） | ✓ | ✓ | - | - |
| Widget 改動（不影響外觀） | ✓ | ✓ | ✓ | - |
| UI 外觀改動（顏色/間距/佈局） | ✓ | ✓ | ✓ | ✓ |
| 新增文件 | ✓ | ✓ | - | - |

## 輸出格式

```
驗證結果：
- Layer 0 (analyze): ✅ No errors
- Layer 1 (test): ✅ N tests passed
- Layer 2 (runtime): ✅ No runtime errors / ⏭️ 跳過（無設備連接）
- Layer 3 (visual): ✅ 外觀正確 / ⏭️ 跳過（非 UI 改動）
```

## Related skills

- **`verification-before-completion`** — the universal "do not claim done without evidence" gate. `flutter-verify` is Flutter's concrete tool chain (`flutter analyze` + `flutter test`); apply `verification-before-completion`'s Gate Function + Rationalization Table on top.
- **`test-driven-development`** — TDD pre-verify pattern. `flutter-verify` runs AFTER the green commit; `test-driven-development` produces the failing-then-passing test cycle.
