---
name: admob-ux-best-practices
description: AdMob banner and native ad placement best practices for mobile apps. Use this skill when the user asks to add, review, or optimize AdMob ads to prevent account bans (accidental clicks) and improve UX.
---

# AdMob UX Best Practices

This skill provides guidelines and safe patterns for placing AdMob ads (especially Banner and Native ads) in mobile applications. The goal is to maximize impressions without compromising User Experience (UX) or risking AdMob account suspension due to "Accidental Clicks".

## 🚨 Critical AdMob Risks (What NOT to do)

1. **Accidental Clicks are Fatal**: Google AdMob strictly penalizes apps with high accidental click rates. Placing ads too close to interactive elements will lead to "Ad Serving Limits" or permanent account suspension.
2. **The Keyboard Trap**: Ads placed at the absolute bottom of a screen containing text inputs are extremely dangerous. When the system keyboard appears, the ad is pushed up, often directly under the user's thumb or right next to the send button.
3. **Banner Blindness (Spammy UX)**: Placing a banner at the bottom of *every single page* makes the app feel cheap. Users develop "banner blindness", lowering your overall eCPM while ruining the premium feel of the app.

## ✅ Safe Placement Patterns

### 1. Chat Interfaces (High Risk)
**DO NOT** place banners at the bottom near the text input/send button.
**DO**:
- Place the `AdBannerWidget` at the **absolute top** of the chat view (just below the `AppBar` and above the scrolling message list).
- Top placement is visually safe, out of the way of the keyboard, and guarantees no accidental clicks during rapid typing.

### 2. ListView / Scrollable Feeds
**DO NOT** sticky a banner at the bottom of a list if it obscures content or sits immediately above system navigation bars (unless carefully padded).
**DO**:
- **Inline Insertion**: Insert the banner ad *as a standard list item* (e.g., between an introductory summary card and the actual list items, or repeating after every Nth item).
- **Inline Adaptive Banners**: AdMob officially recommends `getCurrentOrientationInlineAdaptiveBannerAdSize` for banners placed inside scrolling lists. This dynamically sizes the ad to maximize performance without breaking scrolling.
- **Native Ads**: For an even cleaner experience, use `NativeAd` formatting (`NativeTemplateStyle`) so the ad matches the look and feel of your app's standard list items, drastically reducing "Banner Blindness".
- This acts as a "faux native ad", scrolling naturally with the content and providing a much cleaner, less intrusive look.

### 3. Dashboard / Hub Screens
**DO**:
- A bottom-anchored "Sticky Banner" is acceptable on the main hub *only if* there are no interactive tabs, forms, or high-frequency buttons immediately adjacent to it. Always provide adequate padding.
- **Avoid "Sandwiching"**: Do not sandwich ads between interactive app content and navigation/menu buttons.

### 4. Pages to Exclude Ads Completely
- **Settings/Configuration Pages**.
- **Form/Input Pages**: Any page requiring the user to fill out data, create an item, or edit settings.
- **Loading / Transition / Splash Screens**.
- **Game Play / High Interaction Screens**: Avoid placing banners where the user's fingers are constantly tapping.

## 💡 Implementation Examples (Flutter)

**1. Safe Chat Layout (Top Banner):**
```dart
Column(
  children: [
    if (!isPro) const AdBannerWidget(), // ✅ SAFE: Top of screen
    Expanded(child: MessageListView()),
    ChatInputBar(), // ✅ Safe from keyboard push-up
  ],
)
```

**2. Safe List Layout (Inline Native-style):**
```dart
ListView(
  children: [
    SummaryCard(), // e.g. "Total Active Sessions"
    if (!isPro) const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: AdBannerWidget(), // ✅ SAFE: Scrolls naturally with content
    ),
    SectionTitle('Items'),
    ...items.map((e) => ItemCard(e)),
  ],
)
```

## ⚠️ Adaptive Banner Width=0 Guard (Critical)

**Problem**: On first render, `MediaQuery.of(context).size.width` may return 0 because the widget tree hasn't completed layout. Sending an ad request with width=0 causes:
- AdMob SDK rejects with `LoadAdError(code: 0, message: Invalid ad width or height.)`
- Wasted ad request quota — too many failures degrade fill rate and eCPM
- No retry — ad never loads for that widget's lifecycle

**Root Cause**: `didChangeDependencies()` fires before the first layout pass completes, so `MediaQuery` may not have valid dimensions yet.

**Required Pattern** — Always guard width before requesting an ad:
```dart
Future<void> _loadAdIfNeeded() async {
  if (_bannerAd != null) return;

  final width = MediaQuery.of(context).size.width.truncate();

  // MediaQuery not ready yet — retry next frame
  if (width <= 0) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAdIfNeeded();
    });
    return;
  }

  // Safe to request ad
  final banner = await adService.createInlineAdaptiveBanner(adWidth: width, ...);
}
```

**Why `addPostFrameCallback`**: It schedules the retry after the current frame's layout pass, guaranteeing `MediaQuery` has valid dimensions. This is Google's recommended approach.

**Never do**:
- Send ad requests with width=0 and hope for the best
- Use arbitrary `Future.delayed()` timers as a workaround
- Ignore the error because "it resolves itself" — it doesn't (the ad stays unloaded)

## 🔒 SDK Initialization Guard

**Problem**: Calling ad SDK methods before initialization causes fatal crashes (e.g., RevenueCat `Purchases has not been configured`).

**Required Pattern** — Guard all SDK calls with an `isConfigured` check:
```dart
// Service layer
class RevenueCatService {
  bool _isConfigured = false;
  bool get isConfigured => _isConfigured;

  Future<void> initialize() async {
    if (apiKey.isEmpty) return; // Skip if no keys
    await Purchases.configure(PurchasesConfiguration(apiKey));
    _isConfigured = true;
  }
}

// Provider layer
@Riverpod(keepAlive: true)
Stream<CustomerInfo> customerInfo(Ref ref) {
  final controller = StreamController<CustomerInfo>();
  if (!RevenueCatService.instance.isConfigured) {
    ref.onDispose(() => controller.close());
    return controller.stream; // Empty stream, no crash
  }
  // ... normal SDK calls
}
```

**Applies to**: RevenueCat, MobileAds, Firebase, any SDK that requires explicit initialization before use.

## 🔄 General Workflow
When a user asks to "add ads to the app":
1. Review the UI architecture of the target page.
2. Determine if it is a Form/Chat (use Top placement) or a Feed/List (use Inline placement).
3. Ensure there is conditional logic (e.g., `if (!isPro)`) to hide ads for paid users.
4. **Guard adaptive banner width**: Always check `width > 0` before requesting ads, retry with `addPostFrameCallback` if not ready.
5. **Guard SDK initialization**: Ensure `isConfigured` checks before any SDK calls.
6. **Use `getPlatformAdSize()`**: Always update container height after ad load (see below).
7. **Use test ad IDs in debug**: Switch to Google's official test IDs in debug builds.
8. Verify tests pass without layout constraint errors.

## 🎯 Riverpod: `shouldShowAdsProvider` Pattern

When the app has IAP (Pro subscription via RevenueCat), use a centralized provider to control ad visibility:

```dart
// ad_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Import your IAP provider that exposes isProProvider
import 'iap_provider.dart'; // adjust path as needed

/// Centralized "should show ads" control — Pro users see no ads
final shouldShowAdsProvider = Provider<bool>((ref) {
  final isPro = ref.watch(isProProvider).maybeWhen(
        data: (v) => v,
        orElse: () => false, // Show ads while loading (conservative)
      );
  return !isPro;
});
```

**Usage in widgets:**
```dart
// In any screen that conditionally shows ads:
final showAds = ref.watch(shouldShowAdsProvider);
if (showAds) ...[
  const AdBannerWidget(),
],
```

> [!TIP]
> The `orElse: () => false` default means "not Pro = show ads" even while the RC status
> is still loading. If you prefer to **hide ads while loading** (less aggressive), use
> `orElse: () => true` (assume Pro until proven otherwise).

## 🔥 Inline Adaptive Banner height=0 (CRITICAL)

**Problem**: `AdSize.getCurrentOrientationInlineAdaptiveBannerAdSize(width)` and `AdSize.getInlineAdaptiveBannerAdSize(width, maxHeight)` both return `height=0` in the initial `AdSize` object. If you use `adSize.height` for SizedBox → the banner is invisible (height=0).

**Root Cause**: Inline adaptive banners don't know their actual height until after the ad loads. The SDK determines the optimal height at load time based on the creative received.

**Official Google Pattern** (from [developers.google.com/admob/flutter/banner/inline-adaptive](https://developers.google.com/admob/flutter/banner/inline-adaptive)):

```dart
// In your state/provider:
class AdState {
  final BannerAd? bannerAd;
  final bool isBannerLoaded;
  final AdSize? bannerAdSize; // ← stores REAL size from getPlatformAdSize()
}

// In onAdLoaded callback:
onAdLoaded: (ad) async {
  final bannerAd = ad as BannerAd;
  final platformSize = await bannerAd.getPlatformAdSize();
  if (platformSize == null) return;
  state = state.copyWith(
    bannerAd: bannerAd,
    isBannerLoaded: true,
    bannerAdSize: platformSize, // ← USE THIS for SizedBox
  );
},

// In the UI — MUST use bannerAdSize, NOT bannerAd.size:
if (adState.isBannerLoaded &&
    adState.bannerAd != null &&
    adState.bannerAdSize != null)  // ← guard: only show when real size known
  SizedBox(
    width: adState.bannerAdSize!.width.toDouble(),
    height: adState.bannerAdSize!.height.toDouble(),  // ← REAL height
    child: AdWidget(ad: adState.bannerAd!),
  ),
```

**Never do**:
- Use `bannerAd.size.height` for inline adaptive — it's always 0
- Use `ConstrainedBox` / unconstrained containers hoping AdWidget self-sizes
- Skip `getPlatformAdSize()` — your banner will be invisible

**Banner type comparison**:
| Type | Initial height | Use case | Fill rate |
|------|---------------|----------|-----------|
| `AdSize.banner` (320×50) | 50 (correct) | Simple, fixed | Lower in some regions |
| Anchored Adaptive | Async API | Fixed position (top/bottom) | Medium |
| Inline Adaptive | **0** (needs getPlatformAdSize) | Scrollable lists | **Highest** |
| Inline Adaptive + maxHeight | **0** (needs getPlatformAdSize) | Fixed position with cap | High |

## 🧪 Debug/Release Test Ad IDs (Required)

**Problem**: New ad units often return NO_FILL (error code 3) in development because AdMob hasn't built up enough user data for the app. This makes it impossible to verify ad UI placement during development.

**Required Pattern** — Use Google's official test ad IDs in debug builds:

```dart
import 'package:flutter/foundation.dart';

// Google official test ad unit IDs (100% fill rate guaranteed)
// https://developers.google.com/admob/android/test-ads
const _testBannerAndroid = 'ca-app-pub-3940256099942544/9214589741';
const _testBannerIos = 'ca-app-pub-3940256099942544/2435281174';
const _testInterstitialAndroid = 'ca-app-pub-3940256099942544/1033173712';
const _testInterstitialIos = 'ca-app-pub-3940256099942544/4411468910';
const _testNativeAndroid = 'ca-app-pub-3940256099942544/2247696110';
const _testNativeIos = 'ca-app-pub-3940256099942544/3986624511';

// In your AdNotifier/AdService:
String get _bannerAdUnitId => kDebugMode
    ? (Platform.isAndroid ? _testBannerAndroid : _testBannerIos)
    : (Platform.isAndroid
        ? AppConstants.adMobBannerIdAndroid
        : AppConstants.adMobBannerIdIos);
```

**Benefits**:
- Test ads always fill (100% fill rate) — you can verify UI placement
- Test ads show a "Test Ad" label — easy to identify
- No risk of invalid traffic violations from clicking test ads
- Production ads only used in release builds where real users interact

## 🔍 NO_FILL Debugging (Error Code 3)

**Problem**: `Ad failed to load : 3` means AdMob has no ad inventory to serve for this request. Common causes:

| Cause | Solution |
|-------|----------|
| New app/ad unit (< 24-48h) | Wait — AdMob needs time to build inventory |
| Low traffic region | Normal — fill rates vary by country |
| Repeated requests same device | AdMob throttles — stop spam-testing |
| Standard 320×50 in low-fill region | Switch to Adaptive (wider ad pool) |
| Debug builds hitting prod IDs | Use test ad IDs in debug (see above) |

**Debugging steps**:
1. Check logcat/console for `Ad failed to load : N` (N = error code)
2. Error codes: 0=Internal, 1=Invalid request, 2=Network, **3=NO_FILL**
3. If NO_FILL: switch to test IDs to verify code is correct
4. If test ad loads: code is fine, NO_FILL is an inventory issue
5. Production fill rate improves with: more users, longer ad unit age, broader ad formats

## ⚠️ Interstitial Callback Ordering

**Per Google docs**: `fullScreenContentCallback` should be set before calling `show()`. However, the cascade syntax (`..show()..fullScreenContentCallback`) is also commonly used. The critical requirement is that `dispose()` is called in both `onAdDismissed` and `onAdFailedToShow` to prevent memory leaks.

```dart
onAdLoaded: (ad) {
  ad.fullScreenContentCallback = FullScreenContentCallback(
    onAdDismissedFullScreenContent: (ad) => ad.dispose(),
    onAdFailedToShowFullScreenContent: (ad, error) => ad.dispose(),
  );
  ad.show();
},
```

## Related skills

- **`firebase-flutter-setup`** → **`firebase-auth-manager`** → **`admob-ux-best-practices`** — use in sequence for monetized apps. Firebase sets up the backend, auth implements sign-in, admob-ux-best-practices integrates ads responsibly.
- **`revenuecat-manager`** — use alongside admob-ux-best-practices for monetization. Admob handles ads; revenuecat handles subscriptions.

