---
name: flutter-listview-viewport-gotchas
description: Flutter ListView/CustomScrollView viewport recycling gotchas and debugging patterns. Use when debugging Flutter issues where widget state changes do not reflect in the UI, `didUpdateWidget` is never called, `ScrollController` has no clients, or selected items in horizontally scrollable lists are not visible. Triggers on keywords like "didUpdateWidget not called", "ListView recycling", "widget state lost", "scroll to selected", "chip not visible", "ScrollController hasClients false", "StatefulWidget disposed unexpectedly", "ConsumerStatefulWidget state lost".
---

# Flutter ListView Viewport Recycling Gotchas

## Core Problem

`ListView`, `CustomScrollView`, and `GridView` are **viewport-based** — they only keep widgets that are within or near the visible area mounted in the widget tree. Widgets scrolled out of view are **disposed** and their State is destroyed. When the parent calls `setState`, disposed children are **recreated from scratch** (new `State`, `initState` called) rather than updated (`didUpdateWidget` called).

This causes several classes of bugs:

## Bug Pattern 1: `didUpdateWidget` Never Called

**Symptom**: A `StatefulWidget` inside a `ListView` should react to prop changes via `didUpdateWidget`, but logcat shows `didUpdateWidget` is never triggered.

**Root cause**: The widget was scrolled out of view → disposed → recreated as a new instance after `setState`.

**Fix**: Duplicate prop-change logic in **both** `initState` and `didUpdateWidget`:

```dart
class _MyWidgetState extends State<MyWidget> {
  @override
  void initState() {
    super.initState();
    // Handle initial state (covers recreation after viewport recycling)
    if (widget.selectedId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelected();
      });
    }
  }

  @override
  void didUpdateWidget(covariant MyWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Handle prop changes (covers normal widget updates without recycling)
    if (oldWidget.selectedId != widget.selectedId && widget.selectedId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToSelected();
      });
    }
  }
}
```

## Bug Pattern 2: `ScrollController.hasClients` is false

**Symptom**: `ScrollController` reports `hasClients == false` in `addPostFrameCallback`, even though the `ScrollView` is in the widget tree.

**Common causes**:
1. **`LayoutBuilder` wrapping `ScrollView`**: `LayoutBuilder` can delay the build by one frame, causing the `ScrollController` to not be attached yet when `addPostFrameCallback` fires.
2. **Widget not yet laid out**: The `ScrollView` exists in the widget tree but hasn't been laid out yet.

**Fix**: Remove unnecessary `LayoutBuilder` wrappers. If `LayoutBuilder` is needed, add a guard:

```dart
void _scrollToSelected() {
  if (!_scrollController.hasClients) return;
  final maxScroll = _scrollController.position.maxScrollExtent;
  if (maxScroll <= 0) return;
  _scrollController.animateTo(maxScroll, duration: Duration(milliseconds: 300), curve: Curves.easeOut);
}
```

## Bug Pattern 3: Selected Item Not Visible in Horizontal ScrollView

**Symptom**: A horizontally scrollable chip/tab picker correctly selects an item (state is set), but the selected chip is clipped off-screen.

**Fix**: Auto-scroll to the selected item when the widget is first created or updated:

```dart
void _scrollToSelected() {
  if (!_scrollController.hasClients) return;
  // Simple approach: scroll to end (works when selected item is rightmost)
  final maxScroll = _scrollController.position.maxScrollExtent;
  if (maxScroll <= 0) return;
  _scrollController.animateTo(maxScroll, ...);
}
```

For precise positioning, use `GlobalKey` on each item and `Scrollable.ensureVisible()`.

## Debugging Checklist

1. **Identify the parent scroll container** — Check if using `ListView`, `CustomScrollView`, or `SliverList` (all viewport-based and recycle widgets).
2. **Use `print()` not `debugPrint()`** — `debugPrint` throttles output and may not appear in `adb logcat`. Use `print()` for reliable logcat output during debugging.
3. **Add prints in both `initState` AND `didUpdateWidget`** — Determines whether the widget was recreated or updated.
4. **Check `dispose()` calls** — Add a print in `dispose()` to confirm whether the widget is being recycled.
5. **Verify `ScrollController` attachment** — Print `_scrollController.hasClients` before using it.

## Prevention Guidelines

- For widgets inside `ListView` that need to preserve state across scrolling, use `AutomaticKeepAliveClientMixin` with `wantKeepAlive => true`.
- Always implement both `initState` and `didUpdateWidget` when the widget should react to prop changes.
- Prefer `SingleChildScrollView` over `ListView` when the number of children is small and recycling is unnecessary.
- Remove `LayoutBuilder` wrappers around `ScrollView` unless `constraints` are actively used.

## Related skills

- **`flutter-verify`** — use to verify viewport behavior on real devices and catch recycling-related regressions.
