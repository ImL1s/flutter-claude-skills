---
name: flutter-unit-testing
description: Use when writing Flutter/Dart unit tests that actually catch bugs - covers Riverpod provider testing with ProviderContainer, pure function testing, boundary/edge cases, and anti-patterns to avoid. Triggers on keywords like "unit test", "provider test", "test coverage", "寫測試", "單元測試".
---

# Flutter Unit Testing That Actually Catches Bugs

## Core Principle

> **Tests must verify REAL behavior, not mock behavior.**
> If your test can't catch a real bug, delete it—it gives false confidence.

## The 5 Laws of Bug-Catching Unit Tests

```
1. Test BEHAVIOR, not implementation
2. Test BOUNDARIES, not just happy path
3. Test ERROR paths explicitly
4. Mock at the LOWEST possible level
5. Every test must have a REASON — "what bug does this catch?"
```

## Flutter/Dart Testing Patterns

### Pattern 1: Pure Function Tests (Highest Value)

Extract logic into pure functions and test directly — zero mocking needed.

```dart
// ✅ GOOD: Pure function, directly testable
@visibleForTesting
WasteCategory mapWasteCategory(String raw) {
  final text = raw.toLowerCase();
  if (text.contains('hazard') || text.contains('有害')) return WasteCategory.hazardous;
  if (text.contains('recycl') || text.contains('回收')) return WasteCategory.recyclable;
  return WasteCategory.unknown;
}

test('maps Chinese hazardous terms correctly', () {
  expect(mapWasteCategory('有害廢棄物'), WasteCategory.hazardous);
  expect(mapWasteCategory('電池'), WasteCategory.hazardous);
});

test('handles mixed case and whitespace', () {
  expect(mapWasteCategory('  RECYCLABLE  '), WasteCategory.recyclable);
});

test('returns unknown for unrecognized input', () {
  expect(mapWasteCategory('asdf'), WasteCategory.unknown);
  expect(mapWasteCategory(''), WasteCategory.unknown);
});
```

**Bug this catches:** Incorrect category mapping → wrong disposal advice to user.

### Pattern 2: Riverpod Provider Tests

```dart
// Use ProviderContainer for isolated provider testing
test('favorites toggle adds then removes', () {
  final container = ProviderContainer.test(
    overrides: [
      // Override SharedPreferences or repository
      sharedPreferencesProvider.overrideWithValue(FakeSharedPreferences()),
    ],
  );

  final notifier = container.read(favoritesProvider.notifier);

  // Act: toggle on
  notifier.toggle('stop-123');
  expect(container.read(favoritesProvider), contains('stop-123'));

  // Act: toggle off
  notifier.toggle('stop-123');
  expect(container.read(favoritesProvider), isNot(contains('stop-123')));
});
```

**Key rules:**
- Use `ProviderContainer.test()` (auto-disposes)
- Override only external dependencies (DB, network)
- Test state transitions, not internal implementation
- Verify provider interactions through state changes

### Pattern 3: Boundary & Edge Case Testing

```dart
group('boundary cases that catch real bugs', () {
  test('empty list does not crash', () {
    final result = findNearestStop([]);
    expect(result, isNull);
  });

  test('single item list returns that item', () {
    final result = findNearestStop([onlyStop]);
    expect(result, equals(onlyStop));
  });

  test('exactly at boundary distance', () {
    // 3000m is the cutoff — test AT the boundary
    final result = findWithinRadius(stops, 3000);
    expect(result, contains(stopAt3000m)); // or not? clarify spec
  });

  test('negative values handled gracefully', () {
    expect(() => calculateDistance(-91, 0, 0, 0), throwsArgumentError);
  });

  test('unicode and special characters in input', () {
    final result = parseScheduleAddress('忠孝路28號（A03路線）');
    expect(result.address, '忠孝路28號');
  });
});
```

### Pattern 4: Error Path Testing

```dart
test('network timeout returns friendly error message', () {
  final result = friendlyError(SocketException('timeout'));
  expect(result, contains('網路連線異常'));
});

test('rate limit returns retry message', () {
  final result = friendlyError(Exception('429 too many requests'));
  expect(result, contains('繁忙'));
});

test('unknown error does not expose internals', () {
  final result = friendlyError(Exception('NullPointerException at line 42'));
  expect(result, isNot(contains('NullPointerException')));
  expect(result, contains('暫時不可用'));
});
```

**Bug this catches:** Error messages leaking stack traces to users.

## Anti-Patterns to AVOID

### ❌ Testing Mock Behavior
```dart
// BAD: You're testing that Mockito works, not your code
verify(mockRepo.fetchData()).called(1);
// This tells you nothing about whether fetchData returns correct data
```

### ❌ No Assertion After Action
```dart
// BAD: Test passes even if function is broken
test('does something', () {
  myFunction();
  // No expect() — what are you testing?
});
```

### ❌ Testing Implementation Details
```dart
// BAD: Breaks when you refactor, even if behavior is unchanged
test('uses cache', () {
  provider.getData();
  verify(mockCache.get('key')).called(1);
  // Tests HOW, not WHAT
});

// GOOD: Test the result, not the path
test('returns cached data on second call', () {
  final first = provider.getData();
  final second = provider.getData();
  expect(first, equals(second));
  // Tests WHAT: same result, regardless of HOW
});
```

### ❌ Fragile Time-Dependent Tests
```dart
// BAD: Fails at midnight or across time zones
test('shows today schedule', () {
  expect(getSchedule(), contains(DateTime.now().toString()));
});

// GOOD: Inject time dependency
test('shows schedule for given day', () {
  final schedule = getScheduleForDay(DateTime(2026, 3, 13));
  expect(schedule, isNotEmpty);
});
```

## Bug-Finding Test Categories (Priority Order)

1. **Data transformation bugs** — Parse/format/convert functions
2. **State transition bugs** — Provider state changes in wrong order
3. **Boundary bugs** — Off-by-one, empty collections, max values
4. **Error handling bugs** — Uncaught exceptions, wrong error messages
5. **Null safety bugs** — Unexpected null values in optional fields
6. **Concurrency bugs** — Race conditions in async providers

## Test Naming Convention

```
test('[WHAT] [WHEN] [THEN]')

// Examples:
test('bearing label returns 東北 when target is northeast')
test('parse classification returns null when JSON is invalid')
test('favorites toggle removes item when already favorited')
```

## Verification Checklist

Before claiming tests are complete:

- [ ] Every public function has at least one test
- [ ] Happy path tested
- [ ] At least 2 edge cases per function (empty, null, boundary)
- [ ] Error paths tested (what happens when things fail?)
- [ ] No tests that ONLY verify mock behavior
- [ ] Test names describe WHAT behavior is being verified
- [ ] All tests pass: `fvm flutter test`
