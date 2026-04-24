---
name: flutter-api-reverse-engineering
description: >
  Reverse engineer Flutter/mobile app APIs using Frida dynamic instrumentation,
  BoringSSL traffic interception, crypto analysis, and standalone client creation.
  Use this skill when the user wants to: reverse engineer a mobile app's API,
  intercept HTTPS traffic from a Flutter app, extract auth tokens or crypto keys
  from Android apps, bypass API encryption/obfuscation layers, create a standalone
  Python API client from a mobile app, hook native libraries with Frida, analyze
  AES/Ed25519/X25519 crypto in stripped binaries, or dump SharedPreferences.
  Triggers on keywords like "逆向", "reverse engineer", "Frida", "intercept API",
  "hook", "ssl_write", "bypass encryption", "extract token", "API client from app",
  "BoringSSL", "libapp.so", "libflutter.so", "decompile APK".
---

# Flutter / Mobile App API Reverse Engineering

A systematic methodology for reverse engineering mobile app APIs, from APK analysis
through to a fully standalone Python API client. Developed and battle-tested on
production Flutter apps with Kiwi SDK encryption, X25519 key exchange, and AES response encryption.

## When to Use

- Reverse engineering any Flutter or native Android app's API
- Intercepting HTTPS traffic that resists standard MITM proxies (certificate pinning, local proxies)
- Extracting auth tokens (JWT, session tokens) from running apps
- Analyzing crypto implementations in stripped native libraries
- Creating standalone API clients that bypass app-level encryption

## Prerequisites

```
Required: Python 3, Frida (pip3 install frida frida-tools), adb, Android emulator or rooted device
Optional: jadx (APK decompilation), blutter (Flutter/Dart AOT analysis)
```

## Phase 1: Static Analysis

Start with static analysis to understand the app's architecture before touching Frida.

### APK Extraction
```bash
# Unpack APK
mkdir apk_extracted && cd apk_extracted
unzip ../app.apk

# List native libraries — these are your hook targets
ls lib/arm64-v8a/
# Common: libflutter.so, libapp.so, lib*.so (custom crypto, SDKs)
```

### Key Files to Examine
```
AndroidManifest.xml  → package name, permissions, services
lib/arm64/           → native .so libraries (hook targets)
assets/              → config files, embedded keys
shared_prefs/        → via adb, auth tokens and settings
```

### Identify the Crypto Stack
```bash
# Search for crypto-related strings in native libs
strings lib/arm64/lib*.so | grep -iE 'aes|ed25519|x25519|curve|sign|encrypt|decrypt|hmac|sha256'

# Check for known SDK libraries
ls lib/arm64/ | grep -iE 'crypto|ssl|curve|kiwi|signal'
```

### Dart/Flutter Specific
```bash
# If blutter is available, analyze libapp.so for Dart symbols
blutter libapp.so output_dir/
# Look for: signature functions, HTTP client classes, key storage
```

## Phase 2: Dynamic Setup

### Frida Server on Device
```bash
# Check device architecture
adb shell getprop ro.product.cpu.abi  # arm64-v8a

# Push and start frida-server
adb push frida-server /data/local/tmp/
adb shell "chmod 755 /data/local/tmp/frida-server"
adb shell "/data/local/tmp/frida-server -D &"

# Verify
adb shell "pidof frida-server"
```

### Enumerate Loaded Modules at Runtime
This is critical — static analysis may miss dynamically loaded libraries.

```javascript
// Frida script to list crypto-relevant modules
var mods = Process.enumerateModules();
var crypto = mods.filter(m => {
    var n = m.name.toLowerCase();
    return n.includes('crypto') || n.includes('ssl') || n.includes('kiwi') ||
           n.includes('curve') || n.includes('sign') || n.includes('sodium');
});
crypto.forEach(m => console.log(m.name + " base=" + m.base + " exports=" +
    m.enumerateExports().length + " syms=" + m.enumerateSymbols().length));
```

## Phase 3: Traffic Interception

The core technique: hook BoringSSL's `ssl_write_chain_func` inside `libflutter.so`
to capture plaintext HTTP before TLS encryption.

### Why This Works
Flutter embeds BoringSSL statically in libflutter.so. Standard MITM proxies fail because:
- Certificate pinning blocks proxy certificates
- Apps may use local proxy SDKs (like Kiwi) that add another TLS layer
- The app's Dart HTTP client only talks to localhost

By hooking at the BoringSSL level, we see plaintext BEFORE encryption.

### Finding ssl_write_chain_func Offset
```bash
# The offset varies by Flutter version. Find it by searching for known patterns:
# 1. Look for SSL_write export (even if not called directly)
# 2. ssl_write_chain_func is typically nearby in .text section
# 3. Search for string references: "SSL_write", "ssl_write"

# In Frida, scan for the function:
var flutter = Process.findModuleByName("libflutter.so");
// Try known offsets or scan for function signatures
```

### The ssl_write Hook Pattern
```javascript
// MUST use spawn mode to catch startup request burst
// frida -f com.package.name -l hook.js

Interceptor.attach(flutter.base.add(SSL_WRITE_OFFSET), {
    onEnter: function(args) {
        var len = args[2].toInt32();
        if (len < 10 || len > 65536) return;
        try {
            var data = args[1].readUtf8String(Math.min(len, 16384));
            if (!data || !/^(GET|POST) /.test(data)) return;
            // Parse HTTP headers from plaintext
            var lines = data.split("\r\n");
            var requestLine = lines[0];
            var headers = {};
            for (var i = 1; i < lines.length; i++) {
                var ci = lines[i].indexOf(": ");
                if (ci > 0) headers[lines[i].substring(0,ci).toLowerCase()] = lines[i].substring(ci+2);
            }
            send({type: "request", requestLine: requestLine, headers: headers});
        } catch(e) {}
    }
});
```

### Spawn vs Attach Mode
- **Spawn mode** (`frida -f package`): Catches startup burst. Most apps send 10-30 API
  requests during launch. This is where auth tokens and initial data loads happen.
- **Attach mode** (`frida -p PID`): For ongoing monitoring. Misses startup burst
  because hooks aren't installed until after app initialization.

**Always try spawn mode first.**

### dlopen Hook for Spawn Mode
Libraries may not be loaded when the script starts. Hook `android_dlopen_ext`:
```javascript
Interceptor.attach(Process.getModuleByName("libc.so").getExportByName("android_dlopen_ext"), {
    onLeave: function() {
        if (!hooked && Process.findModuleByName("libflutter.so")) {
            hooked = true;
            hookSslWrite(Process.findModuleByName("libflutter.so"));
        }
    }
});
```

## Phase 4: Auth Token Extraction

### JWT Tokens
Many apps use JWT for API auth. Look for tokens in:
1. **HTTP headers**: `token:`, `Authorization: Bearer`, `X-Token:`
2. **SharedPreferences**: `adb shell cat /data/data/com.package/shared_prefs/*.xml`
3. **Request bodies**: POST login responses

JWT tokens often have very long expiry (sometimes years). Once captured, they work
standalone without the app.

### Testing Token Directly
```python
import requests
headers = {"token": captured_jwt, "Content-Type": "application/json"}
r = requests.get("https://api.example.com/app/api/account/profile", headers=headers)
print(r.json())  # If code=0, the token works standalone!
```

### The Bypass Discovery Pattern
Many apps have TWO API path sets:
- **Encrypted path** (`/v5/{hash}`, custom headers, signatures) — goes through SDK encryption
- **Plain path** (`/app/api/*`) — works with just JWT token!

Always try the plain API paths first. The encrypted paths may just be obfuscated
mirrors of the same endpoints.

## Phase 5: Crypto Analysis

When responses are encrypted or APIs require signatures, analyze the crypto.

### AES S-box Scanning
Find AES implementations by scanning for the S-box constant:
```javascript
// AES forward S-box starts with: 63 7c 77 7b f2 6b 6f c5
var sbox = Memory.scanSync(module.base, module.size, "63 7c 77 7b f2 6b 6f c5");
// Found? AES is implemented in this library.
```

### MemoryAccessMonitor for Key Extraction
The most powerful technique for extracting crypto keys from stripped binaries:
```javascript
MemoryAccessMonitor.enable([{base: sbox_address, size: 256}], {
    onAccess: function(details) {
        // When AES S-box is read, registers contain the key!
        var ctx = details.context;
        for (var r = 0; r <= 5; r++) {
            var val = ctx["x" + r].readByteArray(32);
            // Check if it looks like a key (ASCII or high-entropy bytes)
        }
        // Re-enable for next access:
        setTimeout(enableMonitor, 50);
    }
});
```

**Timing matters**: S-box fires during key schedule (initialization, registers may
contain zeros) AND during actual encryption (registers contain the real key).
Delay the monitor activation by 5-10 seconds to skip initialization.

### Crypto Constant Scanning
```javascript
// Scan for crypto algorithm signatures in stripped binaries:
var patterns = {
    "Ed25519 basepoint": "58 66 66 66 66 66 66 66",
    "X25519 basepoint":  "09 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00",
    "AES S-box":         "63 7c 77 7b f2 6b 6f c5",
    "ChaCha20":          "65 78 70 61 6e 64 20 33",  // "expand 3"
    "ARM NEON AESD":     "?? 58 28 4e",  // Hardware AES decrypt
    "ARM NEON AESE":     "?? 48 28 4e",  // Hardware AES encrypt
};
```

### X25519 Key Exchange Pattern
If `secret-key` header changes per-request, it's likely an ephemeral X25519 public key:
```
Client: keypair = X25519_keygen()
Client: secret-key header = Base64(keypair.public)
Server: shared = X25519(server_private, client_public)
Server: aes_key = KDF(shared) → encrypt response
Client: shared = X25519(client_private, server_public)
Client: aes_key = KDF(shared) → decrypt response
```

To extract the private key: search memory near the public key (typically -32 to -64 bytes offset).

### Finding Function Entry Points
When you know an instruction address (from MemoryAccessMonitor backtrace), find the
function start by scanning backwards for ARM64 prologue:
```javascript
function findFuncStart(addr) {
    for (var off = 0; off < 0x800; off += 4) {
        var insn = Instruction.parse(addr.sub(off));
        if (insn.mnemonic === "stp" && insn.opStr.includes("x29")) {
            return addr.sub(off);
        }
    }
    return null;
}
```

## Phase 6: API Replay & Client Creation

### Replay Captured Requests
```python
# Replay with captured headers to verify they work
headers = {
    "x-signature": captured_sig,
    "x-token": captured_token,
    "secret-key": captured_sk,
    # ... all captured headers
}
r = requests.get("https://api.example.com" + captured_path, headers=headers)
# HTTP 200 = replay works (signature has no time validation!)
```

### Building the Standalone Client
Structure the client with:
1. **Multiple login methods**: phone+password, QR code, Frida capture
2. **Token caching**: Save JWT to file with 0o600 permissions
3. **All discovered endpoints**: Organized by category
4. **CLI interface**: argparse with subcommands
5. **Raw mode**: `--path` flag for arbitrary API calls
6. **JSON output**: `--json` flag for scripting

### Security Checklist for Client Code
- Use `subprocess.run()` not `os.system()` (shell injection prevention)
- Set token file permissions to 0o600 (owner-only)
- Don't log tokens to stdout
- Don't hardcode real user data in examples
- Handle HTTP errors gracefully (non-JSON responses)
- Add `.gitignore` for token/credential files

## Phase 7: Documentation

Update architecture notes with:
1. Complete API endpoint map with request/response structure
2. Auth flow (which headers, which endpoints need what)
3. Crypto implementation details (algorithms, key locations, S-box offsets)
4. Library roles (which .so does what)
5. CLI tool inventory with usage examples
6. Known limitations and next steps

## Quick Reference: Frida Patterns

| Technique | Use Case |
|-----------|----------|
| `Interceptor.attach(addr)` | Hook known function entry points |
| `MemoryAccessMonitor` | Catch reads of crypto constants (S-box, basepoints) |
| `Memory.scanSync(base, size, pattern)` | Find crypto constants or strings in memory |
| `Process.enumerateModules()` | List loaded libraries |
| `Instruction.parse(addr)` | Disassemble at address |
| `Stalker.follow(tid)` | Trace execution flow (heavy, use sparingly) |
| `Java.perform()` | Hook Java/Kotlin layer (SharedPreferences, OkHttp) |

## Common Pitfalls

1. **Attach mode misses startup burst** — Always try spawn mode first
2. **Dart AOT functions can't be hooked** — Non-standard ARM64 calling convention crashes
3. **MemoryAccessMonitor fires only once** — Re-enable in the callback with setTimeout
4. **Stripped libraries have 0 exports** — Use Memory.scanSync for constant patterns
5. **Multiple TLS layers** — App → local proxy → server means two TLS hops
6. **AES S-box fires during init** — Delay monitor activation to catch actual encryption
7. **Per-session keys** — Keys change each app launch; capture and use in same session
