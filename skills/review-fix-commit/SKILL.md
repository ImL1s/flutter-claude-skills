---
name: review-fix-commit
description: Review all changed files, fix issues found, run tests, then commit. Use when finishing a feature or bugfix and want a clean commit.
---

# Review-Fix-Commit Skill

一站式 code review → 修復 → 測試 → commit 流程。

## 流程

1. **Review 所有變更檔案**
   - `git diff` 看 staged + unstaged 變更
   - 檢查每個檔案的：dead code、命名不一致、config 問題、安全漏洞、型別錯誤
   - 同時檢查前端和後端的變更
2. **修復發現的問題**
   - Critical issues 直接修
   - Minor issues 也一併修（命名、格式、dead code）
   - 不要做超出 review 範圍的重構
3. **跑完整測試**
   - 執行專案的 test suite
   - 如果測試失敗，先確認 mock 是否與實作一致
   - 修復測試問題後重跑
4. **Commit & Push**
   - 用描述性的 commit message，說明修了什麼
   - 遵循專案既有的 commit message 風格
   - Push 前先告知用戶，取得確認後再 push

## 注意事項
- 不要只看最新的 commit，要看整個 branch 的所有變更
- Review 時如果發現跨專案的檔案被改到，立刻停下來確認
