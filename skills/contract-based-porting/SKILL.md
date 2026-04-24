---
name: contract-based-porting
description: Port native Android/iOS code to Flutter (or any target language) using Contract-Based TDD. Guarantees zero missed features by extracting the complete API surface from the reference project first, writing contract tests, then implementing RED→GREEN. Use when porting Kotlin/Swift/Java to Dart, or any cross-language feature parity task.
---

# Contract-Based Porting: Cross-Language Feature Parity via TDD

## When to Use

- Porting native Android (Kotlin/Java) or iOS (Swift/ObjC) features to Flutter (Dart)
- Ensuring a Flutter app has 100% feature parity with a reference native implementation
- Any cross-language porting task where you need guaranteed completeness
- Migrating from one framework to another (e.g., React→Vue, Express→FastAPI)

## Core Principle

**Never port line-by-line. Port contract-by-contract.**

The #1 failure mode in cross-language porting is missing features — not bugs. The fix is to extract the *entire public API surface* before writing a single line of target code.

## 3-Step Methodology

### Step 1: Extract the Single Source of Truth (SSOT)

Find the **one file** in the reference project that serves as the command/capability registry. Common patterns:

| Language | Pattern | Example |
|----------|---------|---------|
| Kotlin/Android | Registry object | `InvokeCommandRegistry.kt` |
| Swift/iOS | Protocol constants | `ProtocolConstants.swift` |
| TypeScript/Node | Route map | `routes/index.ts` |
| Python/Django | URL patterns | `urls.py` |

**What to extract:**
```
1. All public commands/endpoints/routes → exact string identifiers
2. All capabilities/permissions → exact string identifiers
3. Constructor parameters → each handler's config surface
4. Error codes → all structured error code strings
```

**How to find it:**
```bash
# Kotlin: find the registry
grep -rn 'register\|addCommand\|mapOf.*command' --include="*.kt" | head -20

# Swift: find protocol constants
grep -rn 'static.*let.*command\|case.*=.*"' --include="*.swift" | head -20

# Search for string enums that look like API contracts
grep -rn '"[a-z]+\.[a-z]+"' --include="*.kt" | sort -u
```

### Step 2: Write Contract Tests (RED Phase)

Create a test file that **enumerates every item** from the SSOT and asserts the target project advertises/implements them:

```dart
// Example: command_registry_contract_test.dart
test('must advertise all 31 reference commands', () {
  // SSOT: extracted from InvokeCommandRegistry.kt
  const referenceCommands = <String>{
    'canvas.open', 'canvas.close', 'canvas.inject',
    'screen.record', 'screen.brightness',
    'camera.snap', 'camera.clip',
    // ... all 31
  };

  // Target: what the Flutter app actually advertises
  final advertised = buildNodeCommands(allPermsGranted).toSet();

  // Gap analysis via set difference
  final missing = referenceCommands.difference(advertised);
  final extra = advertised.difference(referenceCommands);

  expect(missing, isEmpty, reason: 'Missing commands: $missing');
  expect(extra, isEmpty, reason: 'Extra commands: $extra');
  expect(advertised.length, referenceCommands.length);
});
```

**This test MUST fail initially** — that's the RED in TDD. The failures tell you exactly what's missing.

### Step 3: Implement Until GREEN

For each missing item from the contract test:

1. **Check if handler exists** — often the handler code is already written but not *advertised*
2. **If handler exists** → just wire it (add to command list, register provider)
3. **If handler missing** → port the reference implementation:
   - Read the reference handler (Kotlin/Swift)
   - Write the equivalent Dart version
   - Focus on the *contract* (inputs/outputs), not the *implementation*

```bash
# Verify after each batch
flutter test test/protocol/command_registry_contract_test.dart
flutter analyze
```

## Advanced Patterns

### Pattern A: UI Wiring Audit

After command parity, audit the **integration layer** — features implemented but not wired to UI:

```bash
# Find all public methods never called outside their own file
grep -rn 'toggleAutoRestart\|seamColorProvider\|TrustPromptDialog' lib/ --include="*.dart" | \
  grep -v '.g.dart\|_test.dart'
# If a method appears only in its definition file → not wired
```

### Pattern B: Error Code Parity

Port the reference error parser for consistent error handling:

```kotlin
// Reference: InvokeErrorParser.kt
// Splits "CAMERA_ERROR: lens not found" → code + message
```

```dart
// Target: invoke_error_parser.dart
ParsedInvokeError parseInvokeErrorMessage(String raw) { ... }
```

### Pattern C: State/Model Field Parity

Compare state classes field-by-field:

```bash
# Reference state fields (Kotlin)
grep -A5 'data class.*State\|val ' ConnectionState.kt

# Target state fields (Dart)
grep -A5 'class.*Snapshot\|final ' gateway_connection_provider.dart
```

Add missing fields (e.g., `seamColorHex`, `tlsFingerprint`) with `copyWith` support.

### Pattern D: Capability Advertising

Capabilities are separate from commands. The reference may advertise capabilities conditionally:

```dart
// Always-on
caps.add('canvas');
caps.add('device');

// Permission-gated
if (perms['camera'] ?? false) caps.add('camera');

// Platform-specific
if (Platform.isAndroid) caps.add('foreground_service');
```

## Verification Checklist

After all contract tests pass:

```bash
# 1. Full test suite (contract + unit + integration)
flutter test

# 2. Static analysis
flutter analyze

# 3. Count parity
echo "Commands: $(grep -c 'expect.*command' test/protocol/command_registry_contract_test.dart)"
echo "Capabilities: $(grep -c 'expect.*capability' test/protocol/command_registry_contract_test.dart)"
```

## Common Mistakes

1. **Porting code without porting the contract first** → guaranteed to miss features
2. **Copying implementation instead of contract** → fragile, wrong idioms
3. **Not checking for "implemented but not wired"** → handler exists, never called
4. **Ignoring conditional logic** → permission/platform gates differ across languages
5. **Skipping error code porting** → gateway receives unstructured errors

## Real-World Results

This methodology was used to port `openclaw-node` (Kotlin+Swift) → `claw_node` (Flutter):
- **31/31 commands** parity (7 were missing-but-implemented)
- **14/14 capabilities** parity
- **5 integration gaps** found and fixed (error parser, voice auto-restart, seam color, trust prompt, session drawer)
- **245 tests**, 0 analysis issues
- Total time: ~2 sessions with zero manual regression testing
