---
name: flutter-device-crud-testing
description: Comprehensive Flutter app CRUD testing on real devices/simulators using Mobile MCP + Dart MCP. Use when user asks to "test all pages", "verify all buttons", "run device CRUD test", "全頁面測試", "模擬器測試", "跑一遍所有按鈕". Triggers on keywords like "test all screens", "CRUD test", "device test", "tap every button", "full page test".
---

# Flutter Device CRUD Testing — Mobile MCP + Dart MCP

Systematically test **every interactive element** of a Flutter app on a real device or emulator using Mobile MCP (screenshot/tap/swipe/type) and Dart MCP (launch/hot_reload/runtime_errors/widget_tree/flutter_driver).

## When to Use

- Before release, to validate all pages visually and functionally
- After dark mode / theme changes, to verify readability
- After refactoring, to confirm no regressions
- When user says "跑一遍", "test all screens", "verify every button"

---

## Phase 0: Pre-flight — Codebase Analysis

Before touching any device, understand the app structure:

### 0.1 Read Router/Navigation
```
Find the app's router file (usually app_router.dart, router.dart, or main.dart):
- GoRouter: look for GoRoute, ShellRoute definitions
- Navigator 2.0: look for Router, RouteInformationParser
- Navigator 1.0: look for MaterialPageRoute, pushNamed calls

Output: List of ALL navigable screens with their paths.
```

### 0.2 Analyze Each Screen
```
For each screen .dart file, catalogue:

INTERACTIVE ELEMENTS:
├── Buttons: ElevatedButton, TextButton, IconButton, FloatingActionButton
├── Inputs: TextField, TextFormField, SearchBar
├── Selection: ChoiceChip, FilterChip, Switch, Checkbox, Radio
│             SegmentedButton, DropdownButton, PopupMenuButton
├── Navigation: InkWell/GestureDetector with push/go/pop
│              ListTile with onTap, Card with onTap
├── Scrollable: RefreshIndicator, ListView, GridView, CustomScrollView
├── Dialogs: showDialog, showModalBottomSheet, showSnackBar
└── Special: Slider, DatePicker, TimePicker, ExpansionTile

EXPECTED BEHAVIORS:
├── CRUD: API calls, state mutations, provider updates
├── Navigation: route changes, page transitions, back navigation
├── UI Feedback: SnackBar, Toast, Dialog, loading indicator, shimmer
├── Validation: required field checks, format checks, error messages
└── State changes: toggle on/off, expand/collapse, select/deselect
```

### 0.3 Build Test Matrix

| # | Screen | Element | Action | Tool(s) | Expected Result |
|---|--------|---------|--------|---------|-----------------|
| 1.1 | Dashboard | — | Screenshot | take_screenshot | Layout correct |
| 1.2 | Dashboard | RefreshIndicator | swipe(down) | swipe_on_screen | Data refreshes |
| 1.3 | Dashboard | Item card | Tap | list_elements→click | Nav to detail |
| 1.4 | Detail | Back button | Tap | click | Returns to list |
| 2.1 | Form | Name field | Type text | click→type_keys | Text appears |
| 2.2 | Form | Submit (empty) | Tap | click | Validation error |
| 2.3 | Form | Submit (filled) | Tap | click | Success feedback |
| 3.1 | Settings | Theme toggle | Tap | click | Theme changes |
| 3.2 | Settings | Switch | Toggle | click | State flips |

---

## Phase 1: Setup & Launch

### 1.1 Identify Device
```
→ mobile_mcp list_available_devices
→ Pick iOS Simulator or Android Emulator
→ Prefer a named testing device (e.g., "E2E-iPhone16Pro")
→ Note the device ID for all subsequent calls
```

### 1.2 Launch App
```
→ dart_mcp launch_app(root=<project_root>, device=<device_id>)
→ Returns DTD URI — save it!
→ ⚠️ First launch can take 60-120 seconds for iOS Simulator
```

### 1.3 Connect Dart Tooling Daemon
```
→ dart_mcp connect_dart_tooling_daemon(uri=<dtd_uri>)
→ This enables: runtime errors, hot reload, widget tree
```

### 1.4 Verify Launch
```
→ mobile_mcp take_screenshot(device)
→ Confirm app is on screen and not showing a crash/error
→ Save screenshot as baseline
```

### ⚠️ Launch Troubleshooting

| Symptom | Fix |
|---------|-----|
| `launch_app` hangs >3 min | Kill zombie Flutter processes: `flutter_driver` or `dart` processes. Check with `ps aux \| grep flutter` |
| DTD URI connection fails | Re-launch the app, get fresh URI. **Never reuse old URIs.** |
| App shows white screen | Check `get_runtime_errors()` — likely a provider/init crash |
| Simulator not found | Run `xcrun simctl list devices` or check Android emulator is running |
| "No supported devices" | Ensure device platform matches app targets (iOS/Android) |

---

## Phase 2: Execute Tests — Screen by Screen

### Core Loop: For each screen

```
NAVIGATE → SCREENSHOT → INTERACT → VERIFY → RECORD
```

### Step A: Navigate to Screen

**Bottom Tab Navigation (most common):**
```
1. mobile_mcp list_elements_on_screen(device)
2. Find tab label by text (e.g., "Home", "Settings", "Profile")
3. mobile_mcp click_on_screen_at_coordinates(device, x, y)
4. Wait 1-2 seconds for animation
```

**Push Navigation (detail pages):**
```
1. Find the trigger element (list item, card, button)
2. Tap it → app pushes new route
3. Verify new screen loaded via screenshot
```

**Deep Link / Direct Navigation (if supported):**
```
1. Use mobile_mcp open_url(device, url) for deep links
```

### Step B: Screenshot Initial State
```
→ mobile_mcp take_screenshot(device)
→ Save screenshot path for walkthrough
→ This is your BEFORE state
```

### Step C: Test Each Interactive Element

Process elements **top to bottom, left to right** on the screen.

**For each element:**
```
1. LOCATE
   → mobile_mcp list_elements_on_screen(device)
   → Find element by text, accessibility label, or type
   → ⚠️ NEVER guess coordinates — ALWAYS call list_elements first

2. TRIGGER ACTION
   → Button/Chip/Toggle: click_on_screen_at_coordinates(device, x, y)
   → Text input: click(field) → type_keys(device, text, submit=false)
   → Scroll: swipe_on_screen(device, direction, distance)
   → Pull-to-refresh: swipe_on_screen(device, direction="down", y=300)

3. VERIFY RESULT
   → mobile_mcp take_screenshot(device)          // Visual check
   → dart_mcp get_runtime_errors()                // Zero-crash check
   → mobile_mcp list_elements_on_screen(device)   // New UI state

4. RECORD
   → Save screenshot + pass/fail status
   → If error: save error details + screenshot as evidence
```

### Step D: Edge Cases per Screen Type

**Form Screens:**
```
- [ ] Submit empty form → expect validation error (SnackBar/inline)
- [ ] Submit with only partial fields → expect specific field error
- [ ] Submit with valid data → expect success feedback
- [ ] Submit twice rapidly → no duplicate submission
- [ ] Type very long text → no overflow / text truncation is graceful
```

**List Screens:**
```
- [ ] Empty state → appropriate "no data" message
- [ ] Pull-to-refresh → RefreshIndicator appears, data reloads
- [ ] Scroll to bottom → no overflow, footer visible or infinite scroll works
- [ ] Tap item → navigates to detail
- [ ] Swipe item (if dismissible) → delete/archive action
```

**Detail Screens:**
```
- [ ] Back navigation → returns to previous screen with state preserved
- [ ] Action buttons (edit/delete/share) → appropriate action or confirmation
- [ ] Scroll through all content → no clipping or overflow
```

**Settings Screens:**
```
- [ ] Toggle switches → state persists after leaving and returning
- [ ] Theme change → entire app re-renders correctly
- [ ] Segmented buttons → correct option selected visually
- [ ] External links → url_launcher opens browser/app
```

**Chat/Input Screens:**
```
- [ ] Send message → appears in chat
- [ ] Suggestions/quick actions → tapping sends or fills input
- [ ] Keyboard appears → content scrolls up, not covered
- [ ] Dismiss keyboard → layout returns to normal
```

### Step E: Navigate Back / Cleanup
```
→ Return to stable state before testing next screen
→ Android: mobile_mcp press_button(device, "BACK")
→ iOS: Tap back arrow or swipe right
→ Or tap the next bottom tab directly
```

---

## Phase 3: Cross-Cutting Tests

### 3.1 Theme Testing
```
1. Run core visual checks in default (light) mode
2. Navigate to Settings → switch to Dark mode
3. Re-check EVERY screen for:
   - Text contrast (no invisible text on dark backgrounds)
   - Card backgrounds (not clashing with dark bg)
   - Icon visibility
   - Input field hint text readability
   - SnackBar/Dialog contrast
4. Switch to System mode → verify it follows device setting
```

### 3.2 Rotation Testing (if relevant)
```
→ mobile_mcp set_orientation(device, "landscape")
→ Screenshot each main screen
→ mobile_mcp set_orientation(device, "portrait")
→ Verify layout restored
```

### 3.3 State Persistence Testing
```
1. Fill a form partially
2. Switch to another tab
3. Return to the form tab
4. Verify: data preserved or intentionally cleared?
```

### 3.4 Error State Testing
```
1. Turn off network (if possible on emulator)
2. Trigger API-dependent features
3. Verify: error messages shown, app doesn't crash
4. Turn network back on → verify recovery
```

---

## Phase 4: Validation Checkpoints

### After EVERY action, run:

```python
# 1. Runtime error check — NON-NEGOTIABLE
dart_mcp get_runtime_errors()
# If errors found → STOP, document error, take screenshot

# 2. Visual verification
mobile_mcp take_screenshot(device)
# Save to artifacts directory

# 3. Widget tree check (for deep issues)
dart_mcp get_widget_tree(summaryOnly=true)
# Verify expected widget types are present
```

### Error Handling Decision Tree

```
Error Found?
├── RenderFlex overflow → P2, cosmetic, note and continue
├── Null check error → P0, crash, STOP and fix
├── setState after dispose → P1, memory leak, note and continue
├── Network/API error → Expected in test env? If yes, note. If no, P1.
├── Framework assertion → P0, structural bug, STOP and fix
└── No error → ✅ Continue
```

---

## Phase 5: Common Interaction Patterns

### Tap a Button by Text
```
elements = mobile_mcp list_elements_on_screen(device)
# Find element with matching text → get center coordinates
mobile_mcp click_on_screen_at_coordinates(device, x, y)
```

### Fill a Text Field
```
# 1. Tap the field to focus
mobile_mcp click_on_screen_at_coordinates(device, fieldX, fieldY)
# 2. Type text
mobile_mcp type_keys(device, text="測試文字", submit=false)
# 3. If keyboard blocks next element, dismiss:
#    - Android: mobile_mcp press_button(device, "BACK")
#    - iOS: tap outside the field
```

### Select a ChoiceChip / SegmentedButton
```
elements = mobile_mcp list_elements_on_screen(device)
# Find chip by label text → get coordinates
mobile_mcp click_on_screen_at_coordinates(device, chipX, chipY)
# Verify: chip now shows selected state (different color/style)
```

### Pull-to-Refresh
```
mobile_mcp swipe_on_screen(device, direction="down", y=400)
# Wait ~2 seconds for refresh to complete
mobile_mcp take_screenshot(device)
```

### Scroll Down (to reveal more content)
```
mobile_mcp swipe_on_screen(device, direction="up")
# ↑ swipe UP = scroll DOWN (finger motion direction)
```

### Toggle a Switch
```
# Switches often don't have text labels in list_elements
# Use the coordinates from list_elements for the parent ListTile
mobile_mcp click_on_screen_at_coordinates(device, switchX, switchY)
```

### Navigate via Bottom Tab
```
elements = mobile_mcp list_elements_on_screen(device)
# Bottom nav labels are stable regardless of scroll position
# Find by label text → click
mobile_mcp click_on_screen_at_coordinates(device, tabX, tabY)
```

### Dismiss a Dialog / Bottom Sheet
```
# Option 1: Tap the action button (OK, Cancel, etc.)
mobile_mcp click_on_screen_at_coordinates(device, btnX, btnY)
# Option 2: Tap outside the dialog (on the scrim)
mobile_mcp click_on_screen_at_coordinates(device, 50, 50)
# Option 3: Android back button
mobile_mcp press_button(device, "BACK")
```

### Handle Keyboard Covering Content
```
# After typing in a TextField, keyboard may cover buttons below.
# Solutions:
# 1. Scroll down while keyboard is up
mobile_mcp swipe_on_screen(device, direction="up", distance=300)
# 2. Dismiss keyboard first
mobile_mcp press_button(device, "BACK")  # Android
# 3. Tap outside the text field
mobile_mcp click_on_screen_at_coordinates(device, 200, 100)  # Safe empty area
```

---

## Phase 6: Using Dart MCP Flutter Driver (Advanced)

For programmatic interaction without coordinate guessing:

### Find a Widget by Text and Tap
```
dart_mcp flutter_driver(
  command="tap",
  finderType="ByText",
  text="Submit"
)
```

### Find a Widget by Type
```
dart_mcp flutter_driver(
  command="tap",
  finderType="ByType",
  type="FloatingActionButton"
)
```

### Find a Widget by Key
```
dart_mcp flutter_driver(
  command="tap",
  finderType="ByValueKey",
  keyValueString="submit_button",
  keyValueType="String"
)
```

### Enter Text into a TextField
```
# First tap to focus
dart_mcp flutter_driver(command="tap", finderType="ByType", type="TextField")
# Then enter text
dart_mcp flutter_driver(command="enter_text", text="測試內容")
```

### Get Text Content
```
dart_mcp flutter_driver(
  command="get_text",
  finderType="ByValueKey",
  keyValueString="total_count",
  keyValueType="String"
)
```

### Wait for Widget to Appear
```
dart_mcp flutter_driver(
  command="waitFor",
  finderType="ByText",
  text="Success!",
  timeout="10000"
)
```

### Scroll Into View
```
dart_mcp flutter_driver(
  command="scrollIntoView",
  finderType="ByValueKey",
  keyValueString="footer_widget",
  keyValueType="String",
  alignment="0.0"
)
```

### Get Widget Tree (for debugging)
```
dart_mcp flutter_driver(
  command="get_diagnostics_tree",
  finderType="ByType",
  type="Scaffold",
  diagnosticsType="widget",
  subtreeDepth="3",
  includeProperties="true"
)
```

### ⚠️ Flutter Driver Gotchas
1. **Cannot find tooltips**: ByTooltipMessage only matches Tooltip widgets
2. **ByText is literal**: Must match exactly (case-sensitive, including trailing spaces)
3. **Multiple matches**: If multiple widgets match, it taps the FIRST one found
4. **Nested finders**: Use Descendant/Ancestor for complex widget trees
5. **Timing**: Use `waitFor` before `tap` if the widget loads asynchronously
6. **get_widget_tree first**: Always use `get_widget_tree` before trying to tap widgets via driver so you know exact widget types and text that exist

---

## Phase 7: Reporting

### Structure your walkthrough:

```markdown
# CRUD Test Report — [App Name]

## Test Environment
- Device: [device name and ID]
- Flutter: [version]
- Date: [date]
- Theme tested: Light / Dark / Both

## Summary
| Screen | Tests | Passed | Failed | Errors |
|--------|-------|--------|--------|--------|
| Dashboard | 5 | 5 | 0 | 0 |
| Settings | 8 | 7 | 1 | 0 |
| Form | 6 | 5 | 0 | 1 |
| TOTAL | 19 | 17 | 1 | 1 |

## [Screen Name] — Test Results

### Initial State
![screenshot](file:///path/to/screenshot_initial.png)

### Test 1.1: [Action Description]
- Action: Tapped "Submit" with empty form
- Expected: Validation SnackBar
- Actual: SnackBar shown ✅
- Runtime errors: None ✅
![screenshot](file:///path/to/screenshot_test_1_1.png)

### Test 1.2: [Action Description]
- Action: Tapped "Submit" with filled form
- Expected: Success message
- Actual: ❌ App crashed — RenderFlex overflow
- Runtime errors: "RenderFlex overflowed by 24.0 pixels on the right"
![screenshot](file:///path/to/screenshot_test_1_2.png)

## Issues Found

| # | Screen | Issue | Severity | Status |
|---|--------|-------|----------|--------|
| 1 | Settings | Switch doesn't persist | P2 | TODO |
| 2 | Form | Overflow on submit | P1 | Fixed |

## Fixes Applied During Testing
- [commit/description of fix]
- Used `dart_mcp hot_reload()` to apply fix mid-test
```

---

## Checklist Template

Copy this for each project:

```markdown
## Pre-Test
- [ ] Codebase analyzed: all screens and interactive elements catalogued
- [ ] Test matrix created with expected behaviors
- [ ] Device selected and ready

## Setup
- [ ] App launched on device
- [ ] DTD connected
- [ ] Baseline screenshot taken

## Screen Tests (repeat per screen)
- [ ] Screen [NAME]: Navigate to screen
- [ ] Screen [NAME]: Screenshot initial state
- [ ] Screen [NAME]: Test all buttons/taps
- [ ] Screen [NAME]: Test all inputs
- [ ] Screen [NAME]: Test all toggles/selections
- [ ] Screen [NAME]: Test scroll / refresh
- [ ] Screen [NAME]: Test edge cases (empty, invalid, rapid)
- [ ] Screen [NAME]: Runtime errors = 0
- [ ] Screen [NAME]: Navigate back cleanly

## Cross-Cutting
- [ ] Theme: Dark mode visual verification
- [ ] Theme: Light mode visual verification
- [ ] Navigation: All routes reachable
- [ ] Navigation: Back button works from all screens
- [ ] Forms: Empty submission validation
- [ ] Runtime errors: 0 across all pages

## Reporting
- [ ] Walkthrough created with screenshots
- [ ] Issues table with severity
- [ ] Fixes documented
```

---

## Tips & Gotchas

1. **`list_elements` is essential** — NEVER guess coordinates. Always call `list_elements_on_screen` first. Coordinates change with screen size, orientation, and content.

2. **Take screenshots liberally** — They're your proof of work. Embed them in walkthroughs. Save them with descriptive names.

3. **Check runtime errors after EVERY action** — Not just at the end. Errors can cascade. A single uncaught error can invalidate all subsequent tests.

4. **Keyboard may cover buttons** — After typing, dismiss keyboard via `press_button(BACK)` on Android or tap outside the field on iOS before trying to tap elements below.

5. **Animations take time** — Wait 1-2 seconds after navigation before taking screenshots. Let transitions complete.

6. **Bottom nav coordinates are stable** — They don't change with scroll, so you can reuse coordinates across tests within the same session.

7. **For both themes** — Run the full suite once in light mode, switch to dark via Settings, then rerun key visual checks.

8. **Hot reload for fixes** — If you find and fix a bug mid-test, use `dart_mcp hot_reload()` to apply without restarting. But remember: hot reload doesn't update `const` values or global initializers — use `hot_restart()` for those.

9. **Don't use browser subagents** — Mobile MCP tools are direct device controls. Never try to control a simulator through a browser subagent — it won't work and wastes time.

10. **Device list can change** — If a simulator crashes or disconnects, re-check `list_available_devices` before continuing.

11. **GoRouter ShellRoute = nested Scaffolds** — SnackBars may appear behind bottom navigation. If testing SnackBars, verify they're visible by checking the screenshot carefully.

12. **Save screenshots to artifacts** — Use `mobile_mcp save_screenshot(device, saveTo=<path>)` for persistent storage. `take_screenshot` returns a transient image.

13. **Process cleanup before testing** — Kill zombie processes that may interfere:
    ```
    # Kill lingering Flutter/Dart processes
    pkill -f "flutter_tools"
    pkill -f "dart.*tooling_daemon"
    # Kill stuck Gradle daemons (Android)
    pkill -f "GradleDaemon"
    ```

14. **Timeout on `launch_app`** — iOS Simulator cold starts can take 2+ minutes. If it seems stuck, check if Xcode is doing a first-run compilation.

15. **ChoiceChip testing** — When testing chip selection, verify BOTH:
    - The newly selected chip has selected styling
    - The previously selected chip lost its selected styling

## Related skills

- **`flutter-unit-testing`** — use for isolated widget unit tests without device hardware. flutter-device-crud-testing focuses on multi-device integration scenarios.
- **`flutter-integration-testing`** — use for cross-module widget interactions on devices.
