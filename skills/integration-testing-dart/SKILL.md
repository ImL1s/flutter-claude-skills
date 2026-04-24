---
name: integration-testing-dart
description: Write effective Dart/Flutter integration tests that verify cross-module interactions and end-to-end flows. Use when writing integration tests involving Riverpod providers, service wiring, data flow, or multi-component verification. Triggers on keywords like "integration test", "整合測試", "provider test", "e2e test", "cross-module test".
---

# Effective Dart/Flutter Integration Testing

## What Integration Tests Verify

Integration tests validate that **multiple components work correctly together**. They sit between unit tests (isolated) and E2E tests (full app on device).

```
Unit Test:     [ServiceA] alone
Integration:   [ServiceA] → [ProviderB] → [ServiceC] working together  
E2E (device):  Full app on real device/emulator
```

## Core Principles

### 1. Test the Real Dependency Chain
Integration tests should use **real implementations** wherever possible, only mocking **external boundaries** (network, file system, native plugins).

```dart
// ✅ GOOD Integration Test: Real provider chain, mock only external service
test('dictation flow produces history entry', () async {
  final container = ProviderContainer(overrides: [
    // Mock only the external boundary (audio, STT API)
    sttServiceProvider.overrideWithValue(FakeSttService()),
    llmServiceProvider.overrideWithValue(FakeLlmService()),
    audioServiceProvider.overrideWithValue(FakeAudioService()),
    // Let everything else be REAL
  ]);
  
  final dictation = container.read(dictationProvider.notifier);
  await dictation.startRecording();
  await dictation.stopRecording();
  
  // Verify the real integration: dictation → history
  final history = container.read(historyProvider);
  expect(history, isNotEmpty);
});
```

### 2. Verify Cross-Module Contracts
```dart
// Settings change → Service provider rebuild → Different service used
test('changing STT provider rebuilds sttServiceProvider', () async {
  final container = ProviderContainer(overrides: [
    envConfigProvider.overrideWithValue(mockEnvConfig),
  ]);
  
  // Initial state
  final settings = container.read(settingsProvider.notifier);
  expect(container.read(sttServiceProvider).providerId, 'google');
  
  // Change setting
  settings.setSttProvider('groq');
  
  // Verify the cascade
  expect(container.read(sttServiceProvider).providerId, 'groq');
});
```

### 3. Test State Transitions, Not Just Final State
```dart
test('dictation state transitions through correct sequence', () async {
  final states = <DictationState>[];
  container.listen(dictationProvider, (_, state) {
    states.add(state);
  });
  
  await dictation.startRecording();
  await dictation.stopRecording();
  
  // Verify the progression
  expect(states[0].isRecording, isTrue);
  expect(states.last.isRecording, isFalse);
  expect(states.last.isProcessing, isFalse);
  expect(states.last.polishedText, isNotEmpty);
});
```

## Riverpod Integration Test Patterns

### ProviderContainer for Isolation
```dart
late ProviderContainer container;

setUp(() {
  container = ProviderContainer(overrides: [
    // Only override external dependencies
  ]);
});

tearDown(() {
  container.dispose();
});
```

### Testing Provider Rebuild Chains
```dart
test('provider chain rebuilds correctly on dependency change', () {
  var buildCount = 0;
  container.listen(derivedProvider, (_, __) {
    buildCount++;
  });
  
  // Trigger upstream change
  container.read(upstreamProvider.notifier).update();
  
  // Verify derived provider rebuilt
  expect(buildCount, greaterThan(0));
});
```

### Fake Services vs Mocks
Prefer **fakes** over mocks for integration tests — they implement the full interface with predictable behavior:

```dart
class FakeSttService implements SttService {
  final _controller = StreamController<SttResult>.broadcast();
  
  @override
  String get providerId => 'fake';
  
  @override
  String get modelId => 'fake-1';
  
  @override
  Stream<SttResult> startStreaming({
    required String languageCode,
    int sampleRateHertz = 16000,
    int channelCount = 1,
    String? promptHint,
  }) {
    // Emit a final result after a short delay
    Future.delayed(Duration(milliseconds: 50), () {
      _controller.add(SttResult(
        transcript: 'fake transcript',
        isFinal: true,
      ));
    });
    return _controller.stream;
  }
  
  @override
  void addAudioData(List<int> audioBytes) {}
  
  @override
  Future<void> stopStreaming() async {}
  
  @override
  void dispose() => _controller.close();
}
```

## Integration Test Categories

### 1. Data Flow Tests
Verify data flows correctly through the full pipeline:
```
Audio → STT → Transcript → LLM → Polish → History
```

### 2. Configuration Cascade Tests
Verify settings changes propagate correctly:
```
Settings change → Provider rebuild → Service swap → Correct behavior
```

### 3. Error Propagation Tests
Verify errors at any layer surface correctly:
```dart
test('STT error surfaces to dictation error state', () async {
  final container = ProviderContainer(overrides: [
    sttServiceProvider.overrideWithValue(FailingSttService()),
  ]);
  
  final dictation = container.read(dictationProvider.notifier);
  await dictation.startRecording();
  
  final state = container.read(dictationProvider);
  expect(state.error, isNotNull);
  expect(state.isRecording, isFalse);
});
```

### 4. Quota/Feature Gate Tests
Verify business logic gates work in integration:
```dart
test('free tier blocks polishing after quota exceeded', () async {
  final container = ProviderContainer(overrides: [
    subscriptionProvider.overrideWith(
      () => SubscriptionNotifier()..state = SubscriptionState(
        tier: SubscriptionTier.free,
        monthlyPolishingUsed: 20,
      ),
    ),
  ]);
  
  // Attempt dictation — should fallback to raw transcript
  // ...
  expect(state.polishedText, equals(rawTranscript));
});
```

## File Organization
```
test/
  integration/
    dictation_flow_test.dart        ← Full record→polish→history flow
    settings_cascade_test.dart      ← Settings→provider rebuild
    subscription_gate_test.dart     ← Quota enforcement
  shared/
    providers/
      service_providers_test.dart   ← Provider wiring
```

## Running Integration Tests
```bash
# In-process integration tests (fast, no device needed)
fvm flutter test test/integration/

# On-device integration tests (real device/emulator)
fvm flutter test integration_test/

# Specific test
fvm flutter test test/integration/dictation_flow_test.dart
```

## Key Differences from Unit Tests

| Aspect | Unit Test | Integration Test |
|--------|-----------|-----------------|
| Scope | Single function/class | Multiple modules |
| Dependencies | All mocked | Real where possible |
| Speed | <1ms per test | <100ms per test |
| Failures | Pinpoint exact bug | Show broken contract |
| When to write | Every public method | Every cross-module flow |

## Related skills

- **`flutter-integration-testing`** — **DISAMBIGUATION**: flutter-integration-testing is Flutter-specific integration testing with device/widget verification. integration-testing-dart covers Dart integration test patterns across modules. Use flutter-integration-testing for Flutter widget integration tests; use integration-testing-dart for multi-module Dart integration testing.
- **`test-driven-development`** — use TDD for both unit and integration tests.
- **`testing-anti-patterns`** — audit integration tests to avoid framework mocking.
