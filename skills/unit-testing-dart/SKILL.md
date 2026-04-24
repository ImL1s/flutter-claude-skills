---
name: unit-testing-dart
description: Write effective Dart/Flutter unit tests that actually catch bugs, not just satisfy coverage metrics. Use when writing, reviewing, or improving unit tests in Flutter projects. Triggers on keywords like "unit test", "單元測試", "test coverage", "測試覆蓋", "mock", "mocktail".
---

# Effective Dart/Flutter Unit Testing

## Core Principles

### 1. Test BEHAVIOR, Not Implementation
```dart
// ❌ BAD: Tests implementation details
test('internal counter increments', () {
  expect(service._counter, 0); // Accessing private state
  service.doWork();
  expect(service._counter, 1);
});

// ✅ GOOD: Tests observable behavior
test('doWork produces correct output', () {
  final result = service.doWork();
  expect(result, expectedOutput);
});
```

### 2. Each Test Should Detect At Least One Bug Category

Every test must answer: **"If a developer made this specific mistake, would this test catch it?"**

Bug categories to test:
- **Wrong value**: function returns/sets incorrect data
- **Missing boundary**: off-by-one, empty input, null handling
- **Wrong control flow**: incorrect if/else, missing early return
- **State corruption**: shared state leaks between calls
- **Error swallowing**: exceptions caught and silently ignored
- **Race condition**: async calls executed out of order

### 3. Follow AAA Pattern Strictly
```dart
test('description of expected behavior when condition', () {
  // Arrange — set up preconditions and inputs
  final service = MyService();
  
  // Act — call the method under test
  final result = service.transform('input');
  
  // Assert — verify the expected outcome
  expect(result, 'expected output');
});
```

### 4. Name Tests Like Specifications
```dart
// ❌ BAD
test('test1', () { ... });
test('should work correctly', () { ... });

// ✅ GOOD
test('returns empty list when no items match filter', () { ... });
test('throws ArgumentError when input exceeds max length', () { ... });
test('preserves existing data when copyWith called without that field', () { ... });
```

## Anti-Patterns to Avoid

### ❌ Happy Path Only (THE LIAR)
Most critical anti-pattern. Tests that only verify success paths give false confidence.

```dart
// ❌ Only tests happy path
test('parse works', () {
  final result = parse('{"key": "value"}');
  expect(result['key'], 'value');
});

// ✅ Also tests edges + errors
group('parse', () {
  test('parses valid JSON object', () {
    final result = parse('{"key": "value"}');
    expect(result['key'], 'value');
  });
  
  test('returns empty map for empty JSON object', () {
    expect(parse('{}'), isEmpty);
  });
  
  test('handles null values in JSON', () {
    final result = parse('{"key": null}');
    expect(result['key'], isNull);
  });
  
  test('throws FormatException on invalid JSON', () {
    expect(() => parse('{invalid}'), throwsFormatException);
  });
  
  test('handles unicode characters', () {
    final result = parse('{"key": "你好"}');
    expect(result['key'], '你好');
  });
});
```

### ❌ Over-Mocking (MOCKERY)
```dart
// ❌ Testing mock behavior, not real behavior
test('calls repository exactly once', () {
  verify(() => mockRepo.save(any())).called(1);
  // This tests YOUR mock setup, not the real code
});

// ✅ Test the visible side-effect
test('save persists data retrievable by load', () {
  await service.save(item);
  final loaded = await service.load(item.id);
  expect(loaded, equals(item));
});
```

### ❌ No Assertions (THE FREE RIDE)
```dart
// ❌ Test passes even if code is completely broken
test('process runs', () {
  service.process('data');
  // No assertions!
});
```

### ❌ Giant Test (THE BLOB)
If a test is >30 lines, split it. Each test should verify ONE behavior.

### ❌ Order-Dependent Tests (CHAIN GANG)
Each test MUST be independent. Use `setUp()` / `tearDown()` for isolation.

## Boundary Value Analysis Checklist

For EVERY function parameter, test:

| Category | Values to Test |
|----------|---------------|
| Empty | `''`, `[]`, `{}`, `0` |
| Null | `null` (if nullable) |
| Single | one item, one char |
| Boundary | max-1, max, max+1 |
| Negative | `-1`, negative numbers |
| Special chars | Unicode, emoji, CJK, RTL |
| Type edge | `double.infinity`, `int.max` |

## Dart/Flutter Specific Patterns

### Testing Stream-returning methods
```dart
test('stream emits values then completes', () async {
  final stream = service.getStream();
  expect(
    stream,
    emitsInOrder([
      'first',
      'second',
      emitsDone,
    ]),
  );
});

test('stream emits error on failure', () {
  final stream = service.getStream();
  expect(stream, emitsError(isA<ServiceException>()));
});
```

### Testing async methods
```dart
test('async method completes with result', () async {
  final result = await service.fetchData();
  expect(result, isNotEmpty);
});

test('async method throws on timeout', () {
  expect(
    () => service.fetchData(),
    throwsA(isA<TimeoutException>()),
  );
});
```

### Testing with SharedPreferences (mock)
```dart
setUp(() {
  SharedPreferences.setMockInitialValues({});
});
```

### Testing copyWith patterns
```dart
group('copyWith', () {
  test('preserves all fields when called empty', () {
    final original = MyState(a: 1, b: 'x', c: true);
    final copy = original.copyWith();
    expect(copy.a, original.a);
    expect(copy.b, original.b);
    expect(copy.c, original.c);
  });
  
  test('updates only specified field', () {
    final original = MyState(a: 1, b: 'x');
    final copy = original.copyWith(a: 2);
    expect(copy.a, 2);
    expect(copy.b, 'x'); // unchanged
  });
  
  test('handles nullable field with sentinel pattern', () {
    final withError = MyState(error: 'oops');
    final cleared = withError.copyWith(error: null);
    expect(cleared.error, isNull);
  });
});
```

### Testing JSON round-trip
```dart
test('toJson/fromJson round-trip preserves all fields', () {
  final original = MyModel(
    id: '123',
    name: 'test',
    timestamp: DateTime(2025, 1, 15),
    optional: null,
  );
  final json = original.toJson();
  final restored = MyModel.fromJson(json);
  
  expect(restored.id, original.id);
  expect(restored.name, original.name);
  expect(restored.timestamp, original.timestamp);
  expect(restored.optional, isNull);
});

test('fromJson handles missing optional fields gracefully', () {
  final minimal = MyModel.fromJson({
    'id': '1',
    'name': 'x',
    'timestamp': '2025-01-15T00:00:00.000',
  });
  expect(minimal.optional, isNull); // default value
});
```

## Test Organization

```
test/
  core/
    services/
      my_service_test.dart      ← mirrors lib/core/services/my_service.dart
    utils/
      my_util_test.dart
  features/
    dictation/
      data/
        stt_service_test.dart
```

## Running Tests
```bash
# All tests
fvm flutter test

# Single file
fvm flutter test test/path/to_test.dart

# With coverage
fvm flutter test --coverage

# Specific directory
fvm flutter test test/core/
```

## Related skills

- **`flutter-unit-testing`** — **DISAMBIGUATION**: flutter-unit-testing is Flutter/Dart-specific unit testing with TDD discipline. unit-testing-dart focuses on Dart test patterns and best practices. Use flutter-unit-testing for TDD workflows; use unit-testing-dart for test quality audits.
- **`testing-anti-patterns`** — audit your tests to catch mocking errors, framework mocking, and test-only production code after unit-testing-dart.
