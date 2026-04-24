---
name: flutter-integration-testing
description: Use when writing Flutter integration/widget tests that verify real component interactions - covers widget tests with ProviderScope, navigation testing, form interaction, async state verification, and E2E flows. Triggers on keywords like "integration test", "widget test", "e2e test", "整合測試", "端對端測試".
---

# Flutter Integration Testing That Catches Real Bugs

## Core Principle

> **Integration tests verify that components work TOGETHER correctly.**
> Unit tests prove functions work in isolation. Integration tests prove THE SYSTEM works.

## When to Use Integration vs Unit Tests

| Use Unit Test | Use Integration Test |
|---------------|---------------------|
| Pure logic functions | Widget renders correctly with provider data |
| Data transformations | Navigation between pages works |
| State machine transitions | User interaction flows (tap → state change → UI update) |
| Error message formatting | Multiple providers interacting correctly |
| Single provider logic | Form submission → validation → API → result |

## Flutter-Specific Patterns

### Pattern 1: Widget Test with Real Providers

```dart
testWidgets('favorite button toggles and persists', (tester) async {
  final fakePrefs = FakeSharedPreferences();
  
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(fakePrefs),
      ],
      child: MaterialApp(home: StopDetailPage(stop: testStop)),
    ),
  );
  
  // Verify initial state: not favorited
  expect(find.byIcon(Icons.favorite_border), findsOneWidget);
  
  // Act: tap favorite
  await tester.tap(find.byIcon(Icons.favorite_border));
  await tester.pumpAndSettle();
  
  // Assert: icon changed AND data persisted
  expect(find.byIcon(Icons.favorite), findsOneWidget);
  expect(fakePrefs.getStringList('favorites'), contains(testStop.id));
});
```

**Bug this catches:** UI updates but data doesn't persist (or vice versa).

### Pattern 2: Navigation Integration Test

```dart
testWidgets('tapping map link navigates to map page', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(routerConfig: appRouter),
    ),
  );

  // Navigate to AI assistant
  await tester.tap(find.text('AI 助手'));
  await tester.pumpAndSettle();

  // Simulate map link tap
  // Find the MarkdownBody and trigger onTapLink
  final markdownFinder = find.byType(MarkdownBody);
  // ... trigger link callback

  await tester.pumpAndSettle();

  // Assert: now on map page
  expect(find.byType(MapPage), findsOneWidget);
});
```

### Pattern 3: Async Provider Integration

```dart
testWidgets('loading → data → display flow', (tester) async {
  final fakeRepo = FakeVehicleRepository();
  
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        vehicleRepoProvider.overrideWithValue(fakeRepo),
      ],
      child: MaterialApp(home: MapPage()),
    ),
  );

  // Initially shows loading
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
  
  // Simulate data arrival
  fakeRepo.emitVehicles(testVehicles);
  await tester.pumpAndSettle();
  
  // Shows data
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(find.text('車號 ABC-123'), findsOneWidget);
});
```

### Pattern 4: Error State Integration

```dart
testWidgets('API failure shows error UI with retry', (tester) async {
  final fakeRepo = FakeVehicleRepository();
  
  await tester.pumpWidget(testApp(fakeRepo));
  
  // Simulate error
  fakeRepo.emitError(Exception('Server 500'));
  await tester.pumpAndSettle();
  
  // Shows error message (not raw exception)
  expect(find.text('Server 500'), findsNothing);  // No raw error
  expect(find.textContaining('暫時無法'), findsOneWidget);
  
  // Retry button works
  fakeRepo.willSucceedNext = true;
  await tester.tap(find.text('重試'));
  await tester.pumpAndSettle();
  
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(find.textContaining('資料已更新'), findsOneWidget);
});
```

### Pattern 5: E2E CRUD Flow

```dart
testWidgets('full CRUD: add → view → edit → delete favorite', (tester) async {
  await tester.pumpWidget(testApp());
  
  // CREATE
  await tester.tap(find.byIcon(Icons.favorite_border).first);
  await tester.pumpAndSettle();
  expect(find.byIcon(Icons.favorite), findsOneWidget);
  
  // READ - navigate to favorites
  await tester.tap(find.text('設定'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('我的收藏'));
  await tester.pumpAndSettle();
  expect(find.text(testStop.name), findsOneWidget);
  
  // DELETE
  await tester.tap(find.byIcon(Icons.delete).first);
  await tester.pumpAndSettle();
  expect(find.text(testStop.name), findsNothing);
});
```

## Integration Test Structure

```dart
// test/e2e/feature_name_test.dart

import 'package:flutter_test/flutter_test.dart';

// Helper to create test app with all required overrides
Widget testApp({List<Override>? extraOverrides}) {
  return ProviderScope(
    overrides: [
      // Always override external dependencies
      sharedPreferencesProvider.overrideWithValue(FakeSharedPreferences()),
      locationServiceProvider.overrideWithValue(FakeLocationService()),
      ...?extraOverrides,
    ],
    child: MaterialApp.router(
      routerConfig: appRouter,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}
```

## What to Test in Integration (Bug-Finding Priority)

1. **Cross-widget data flow** — Provider state → Widget display
2. **Navigation with parameters** — Route params arrive correctly
3. **User interaction sequences** — Multi-step flows that exercise real paths
4. **Error recovery** — Error state → retry → success
5. **State persistence** — Data survives page navigation
6. **Responsive layout** — Key UI works at different screen sizes

## Anti-Patterns to AVOID

### ❌ Over-Mocking in Integration Tests
```dart
// BAD: Everything is mocked — you're testing nothing real
testWidgets('page loads', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dataProvider.overrideWithValue(AsyncData(mockData)),
        // 10 more overrides...
      ],
      child: MockPage(), // Even the page is mocked!
    ),
  );
  expect(find.text('mock'), findsOneWidget); // Tests mock, not app
});
```

### ❌ No `pumpAndSettle` After State Change
```dart
// BAD: Assertions before widget tree rebuilds
await tester.tap(find.byIcon(Icons.add));
// Missing: await tester.pumpAndSettle();
expect(find.text('Added'), findsOneWidget); // FLAKY!
```

### ❌ Testing Widget Existence Without Behavior
```dart
// BAD: Only checks widget tree, not behavior
expect(find.byType(ElevatedButton), findsOneWidget);
// So what? Does the button DO anything?

// GOOD: Test the button works
await tester.tap(find.byType(ElevatedButton));
await tester.pumpAndSettle();
expect(someStateChanged, isTrue);
```

## Localization in Tests

Always include localization delegates for widget tests that render localized text:

```dart
MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: PageUnderTest(),
)
```

## Verification Checklist

- [ ] Tests exercise real user flows (not just render checks)
- [ ] External deps (network, DB, GPS) are faked, not the components under test
- [ ] Error states tested (not just happy path)
- [ ] Navigation tested with parameter passing
- [ ] Async loading states verified (loading → data → error)
- [ ] No flaky time-dependent assertions
- [ ] All tests pass: `fvm flutter test`
