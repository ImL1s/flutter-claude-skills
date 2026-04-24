---
name: verify-ui
description: Verify Flutter UI matches Figma or reference design on real device. Use when doing UI work, comparing screens to Figma, checking visual fidelity, or before claiming UI is "done". Triggers on keywords like "verify ui", "check ui", "figma", "UI 驗證", "對一下設計稿", "截圖比對", "pixel perfect", "ui match".
---

# UI Verification

Strict verification flow for comparing Flutter UI against Figma or reference designs on real devices. This exists because Claude has a pattern of guessing at UI changes and claiming they match when they don't — this skill forces actual evidence-based comparison.

## Before any UI change

1. **Confirm branch**: Run `git branch --show-current` — do NOT proceed if on the wrong branch
2. **Get the reference**: Load the Figma design (via Figma MCP `get_design_context`) or reference screenshot the user provides
3. **Screenshot current state**: Take a device screenshot using Mobile MCP or Dart MCP

## Making changes

4. **List every difference** between current state and reference — be specific: padding values, colors, font sizes, alignment, element positions
5. **Fix ALL differences in one pass** — do not fix one thing and declare success
6. **Build and deploy** to the target device

## After changes

7. **Screenshot the result** on device
8. **Compare side-by-side** against the reference — go through each difference from step 4 and confirm it's resolved
9. **Only declare done** when every difference is addressed and you have screenshot evidence

## Rules

- Never say "this should match" — confirm it DOES match with a screenshot
- Never guess at spacing, colors, or sizes — measure from the reference
- If you can't tell from the screenshot, say so — don't fake confidence
- If the user says it doesn't match, they're right — look again more carefully

## Related skills

- **`verify-ui-auto`** — automated visual-verification pipeline (Marionette → Figma → pixel-diff → auto-fix loop). Use when you want CI-like UI verification; this `verify-ui` skill is the manual checklist variant.
- **`visual-verdict`** — JSON-structured verdict format for screenshot-to-reference comparison output. Use as the output spec when `verify-ui` / `verify-ui-auto` produce verdicts consumed by downstream tooling.
