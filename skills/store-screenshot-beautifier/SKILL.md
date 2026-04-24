---
name: store-screenshot-beautifier
description: Create beautified store listing screenshots for App Store and Google Play. Captures raw screenshots from devices, generates AI paw-print/pattern backgrounds, then composites with ImageMagick (background + screenshot + text). Use when preparing app screenshots for store submission. Triggers on keywords like "store screenshots", "上架圖", "截圖美化", "listing images", "screenshots beautify", "store listing".
---

# Store Screenshot Beautifier Skill

Create professional store listing screenshots by compositing real device captures onto AI-generated backgrounds with promotional text overlays.

## Pipeline Overview

```
1. 📸 Capture raw screenshots (mobile-mcp)
2. 🎨 Generate background images (generate_image) — paw prints, patterns, gradients
3. 🔧 Composite with ImageMagick (magick) — background + screenshot + text
4. 📤 Upload via store API skills (google-play-manager / apple-appstore-manager)
```

> [!IMPORTANT]
> **iOS App Store screenshots MUST come from iOS simulator** — using Android screenshots will cause rejection.
> **Google Play screenshots** can come from any Android device.

## Step 1: Capture Raw Screenshots

### Android (physical device)
```bash
# List devices
mcp-mobile-list-available-devices

# Navigate to target screen, then capture
mcp-mobile-take-screenshot(device: "DEVICE_ID")
mcp-mobile-save-screenshot(device: "DEVICE_ID", saveTo: "screenshots/raw/home_en.png")
```

### iOS (simulator)
```bash
# Boot simulator
xcrun simctl boot "iPhone 16 Pro Max"

# Install and launch app
xcrun simctl install booted path/to/App.app
xcrun simctl launch booted com.bundle.id

# Capture via mobile-mcp or xcrun
mcp-mobile-take-screenshot(device: "SIMULATOR_UDID")
# Or:
xcrun simctl io booted screenshot screenshots/raw/ios_home_en.png
```

### Language Switching
If app supports in-app locale switching, navigate to Settings and change language before capturing each locale's screenshots.

> [!WARNING]
> AI-generated content (e.g., AI Advice) is cached. Switching locale only changes UI labels.
> You must trigger a new AI request after switching to get content in the new language.

## Step 2: Generate AI Backgrounds

Use `generate_image` to create pattern backgrounds. **DO NOT include the screenshot in the AI generation** — only generate the background.

### Example Prompts

**Warm amber (for home/main screen):**
```
Abstract background for a mobile app store screenshot. Warm gradient from amber orange (#D4780A) at top to deep chocolate brown (#2C1810) at bottom. Scattered subtle semi-transparent white paw print patterns of various sizes. No text, no devices, no foreground elements. Just a beautiful textured gradient background with paw prints. 1080x1920 portrait orientation.
```

**Cool teal (for activity/tracking screens):**
```
Abstract background for a mobile app store screenshot. Cool gradient from teal blue (#0A7D8C) at top to midnight navy (#0D1B2A) at bottom. Scattered subtle semi-transparent white paw print patterns of various sizes. No text, no devices, no foreground elements. 1080x1920 portrait orientation.
```

**Forest green (for profile/data screens):**
```
Abstract background for a mobile app store screenshot. Nature gradient from forest green (#1B4332) at top to dark teal (#0D262A) at bottom. Scattered subtle semi-transparent white paw print patterns of various sizes. No text, no devices, no foreground elements. 1080x1920 portrait orientation.
```

> [!NOTE]
> AI-generated images are 640×640. This is fine — ImageMagick will resize them to the target canvas.

## Step 3: Composite with ImageMagick

### Google Play Phone Screenshots (1080×1920)

```bash
# Variables
BG="path/to/bg_amber.png"       # AI-generated background
RAW="screenshots/raw/home_en.png" # Raw device screenshot (1080x2400)
OUT="screenshots/store/google_play/home_en.png"

magick "$BG" -resize 1080x1920! \
  \( "$RAW" -resize 860x1520 \) \
  -gravity south -geometry +0+30 -composite \
  -gravity north \
  -font Helvetica-Bold -pointsize 52 -fill white \
  -annotate +0+65 "AI-Powered Walk Score" \
  -font Helvetica -pointsize 26 -fill '#DDDDDD' \
  -annotate +0+135 "Real-time assessment based on weather & dog health" \
  "$OUT"
```

### App Store 6.7" iPhone (1290×2796)

```bash
BG="path/to/bg_amber.png"
RAW="screenshots/raw/home_en.png"
OUT="screenshots/store/app_store/home_en.png"

magick "$BG" -resize 1290x2796! \
  \( "$RAW" -resize 1050x2220 \) \
  -gravity south -geometry +0+40 -composite \
  -gravity north \
  -font Helvetica-Bold -pointsize 64 -fill white \
  -annotate +0+90 "AI-Powered Walk Score" \
  -font Helvetica -pointsize 32 -fill '#DDDDDD' \
  -annotate +0+175 "Real-time assessment based on weather & dog health" \
  "$OUT"
```

### CJK Text (Chinese/Japanese/Korean)

> [!CAUTION]
> **Helvetica does NOT support CJK characters!** Chinese text will silently render as empty or partial.
> Use `Heiti-TC-Medium` (Traditional Chinese) or `Heiti-SC-Medium` (Simplified Chinese).

```bash
# For zh-TW text
magick "$BG" -resize 1080x1920! \
  \( "$RAW" -resize 860x1520 \) \
  -gravity south -geometry +0+30 -composite \
  -gravity north \
  -font Heiti-TC-Medium -pointsize 56 -fill white \
  -annotate +0+65 "AI 智慧散步評分" \
  -font Heiti-TC-Light -pointsize 28 -fill '#DDDDDD' \
  -annotate +0+140 "根據天氣、狗狗健康狀態即時計算" \
  "$OUT"
```

### Available CJK Fonts on macOS

```bash
# List available CJK fonts
magick -list font | grep -i "heiti\|pingfang\|hiragino\|noto"
```

Common choices:
| Font | Language |
|------|----------|
| `Heiti-TC-Medium` | Traditional Chinese (Bold) |
| `Heiti-TC-Light` | Traditional Chinese (Light) |
| `Heiti-SC-Medium` | Simplified Chinese |
| `Hiragino-Sans-W6` | Japanese |

### Available CJK Fonts on Windows

| Font Path | Language |
|-----------|----------|
| `C:\Windows\Fonts\msjhbd.ttc` | Microsoft JhengHei Bold (Traditional Chinese) |
| `C:\Windows\Fonts\msjh.ttc` | Microsoft JhengHei Regular (Traditional Chinese) |
| `C:\Windows\Fonts\msyhbd.ttc` | Microsoft YaHei Bold (Simplified Chinese) |
| `C:\Windows\Fonts\msyh.ttc` | Microsoft YaHei Regular (Simplified Chinese) |

## Step 3b: Composite with Pillow (Windows / no ImageMagick)

When ImageMagick is not installed, use Python Pillow as a drop-in replacement:

```python
from PIL import Image, ImageDraw, ImageFont

CANVAS_W, CANVAS_H = 1080, 1920

# 1. Resize AI background to canvas
bg = Image.open("bg.png").convert("RGBA").resize((CANVAS_W, CANVAS_H), Image.LANCZOS)

# 2. Resize raw screenshot proportionally (DO NOT stretch!)
raw = Image.open("raw.png").convert("RGBA")
scale = 820 / raw.width  # target width = 820
new_w, new_h = 820, int(raw.height * scale)
raw_resized = raw.resize((new_w, new_h), Image.LANCZOS)

# 3. Rounded corners mask
mask = Image.new("L", (new_w, new_h), 0)
ImageDraw.Draw(mask).rounded_rectangle([(0,0),(new_w-1,new_h-1)], radius=30, fill=255)
raw_final = Image.new("RGBA", (new_w, new_h), (0,0,0,0))
raw_final.paste(raw_resized, (0,0), mask)

# 4. Paste centered at bottom
x = (CANVAS_W - new_w) // 2
y = CANVAS_H - new_h - 60
bg.paste(raw_final, (x, y), raw_final)

# 5. Add text (use CJK font for zh-TW!)
draw = ImageDraw.Draw(bg)
title_font = ImageFont.truetype(r"C:\Windows\Fonts\msjhbd.ttc", 52)  # zh-TW
draw.text((CANVAS_W//2, 80), "AI 智慧分析", fill="white", font=title_font, anchor="mt")

bg.convert("RGB").save("final.png")
```

## Multi-Locale Screenshots

> [!IMPORTANT]
> **Each store locale must have matching screenshots.** en-US screenshots should show English UI; zh-TW should show Chinese UI. Do NOT upload identical screenshots to both locales with only the overlay text changed.

### Capturing per-locale raw screenshots

1. **If app supports in-app locale switching**: Switch language in-app, capture screenshots for each locale.
2. **If app uses system locale**: Change device language via `adb shell` or device settings:
   ```bash
   # Android: switch to English
   adb shell "setprop persist.sys.locale en-US; stop; start"
   # Android: switch to Chinese
   adb shell "setprop persist.sys.locale zh-TW; stop; start"
   ```
3. **If app is single-language only** (hardcoded strings): Use the same raw screenshots for all locales, but vary the overlay text. Note this in the store listing description.

### Ad-Free Screenshot Mode (Flutter)

> [!TIP]
> Add a `dart-define` flag to disable ads during screenshot capture sessions:

```dart
// In main.dart or app state
static const _disableAds = bool.fromEnvironment('DISABLE_ADS');

Future<void> _initAds() async {
  if (_disableAds) return; // Skip ads for clean screenshots
  // ... normal ad init
}
```

Then run:
```bash
flutter run --dart-define=DISABLE_ADS=true
```

## Step 4: Dimension Reference

| Platform | Size | Notes |
|----------|------|-------|
| Google Play Phone | 1080×1920 | Min 320px, max 3840px per side, max 2:1 ratio |
| Google Play Feature Graphic | 1024×500 | Required for store listing |
| App Store 6.7" (iPhone 16 Pro Max) | 1290×2796 | Required |
| App Store 6.5" (iPhone 14 Plus/15 Plus) | 1284×2778 | Optional |
| App Store 5.5" (iPhone 8 Plus) | 1242×2208 | Optional |

## Step 5: Upload via API

### Google Play
Use `google-play-manager` skill:
```python
# Delete old + upload new per locale
for lang in ['en-US', 'zh-TW']:
    requests.delete(f"{BASE}/edits/{eid}/listings/{lang}/phoneScreenshots", headers=H)
    for i in range(1, 6):
        with open(f"screenshots/{lang}/screenshot_{i}.png", "rb") as f:
            requests.post(
                f"{UPLOAD}/edits/{eid}/listings/{lang}/phoneScreenshots",
                headers={**H, "Content-Type": "image/png"}, data=f.read()
            )
requests.post(f"{BASE}/edits/{eid}:commit", headers=H)
```

### App Store
Use `apple-appstore-manager` skill — screenshots are uploaded via App Store Connect as part of the version localization.

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| Chinese text renders as "AI" only | Helvetica doesn't support CJK | Use `Heiti-TC-Medium` (macOS) or `msjhbd.ttc` (Windows) |
| Screenshots distorted/stretched | Resized square AI image to portrait | Use ImageMagick composite or Pillow `LANCZOS`, NOT sips stretch |
| AI advice in wrong language | Cached from previous locale | Trigger new AI request after locale switch |
| iOS screenshots rejected | Used Android device screenshots | Must use iOS simulator screenshots |
| `convert` deprecated warning | ImageMagick v7 | Use `magick` instead of `convert` |
| Ads visible in screenshots | AdMob loaded during capture | Use `--dart-define=DISABLE_ADS=true` |
| `magick` not found on Windows | ImageMagick not installed | Use Pillow (Step 3b) as alternative |
| Same screenshots for all locales | Only overlay text changed | Capture separate raw screenshots per locale (see Multi-Locale) |

## Related skills

- **`store-console-playbooks`** — after beautifying screenshots, use this skill to upload them to the store and review store listing.
- **`release-app`** — handle the full release workflow. Beautify screenshots first, then submit via release-app.
