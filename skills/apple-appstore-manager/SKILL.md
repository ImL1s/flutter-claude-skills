---
name: apple-appstore-manager
description: Apple App Store Connect API manager for iOS and macOS app management. Use this skill when managing iOS/macOS apps, in-app purchases, subscriptions, app metadata, TestFlight, app submissions, or adding macOS platform to existing iOS apps via the App Store Connect API. Triggers on keywords like "App Store Connect", "iOS products", "TestFlight", "app submission", "Apple IAP", "iOS subscription", "Mac App Store", "macOS deploy".
allowed-tools: Bash, Read, Write, Grep, Glob
---

# Apple App Store Connect Manager Skill

This skill enables you to manage iOS apps and in-app purchases through the App Store Connect API.

> [!CAUTION]
> ## Mandatory Completion Checklist (IAP / Subscriptions)
> When setting up subscriptions, you MUST complete ALL steps below via API.
> **NEVER skip a step or tell the user "this needs to be done manually on the web".**
> Every step has working API code in this skill.
>
> - [ ] Find app by bundle ID (`GET /v1/apps?filter[bundleId]=...`)
> - [ ] Create subscription group (`POST /v1/subscriptionGroups`)
> - [ ] Create subscriptions with period + review note (`POST /v1/subscriptions`)
> - [ ] Create localizations for ALL target locales (`POST /v1/subscriptionLocalizations`)
> - [ ] **Set pricing via PATCH + equalizations** (see §4. Subscription Pricing — this is NOT manual)
> - [ ] Verify prices via API (`GET /v1/subscriptions/{id}/prices`)
>
> ### Cross-Skill Pipeline (Full IAP Setup)
> A complete IAP setup requires THREE skills in sequence:
> 1. **This skill** (apple-appstore-manager) → Create ASC subscriptions + pricing
> 2. **google-play-manager** → Create Google Play subscriptions + basePlans + activate
> 3. **revenuecat-manager** → Create RC apps/products/offerings/packages/entitlements, get SDK keys

## Known Apps

| Project | Bundle ID | Status |
|---------|-----------|--------|
| YourApp | `com.example.yourapp` | Internal Testing

## Authentication

### Credentials Location
Credentials are stored at:
- **Directory**: `~/.app_store_credentials/`
- **Private Key**: `~/.app_store_credentials/AuthKey_<YOUR_KEY_ID>.p8`
- **Environment**: `~/.app_store_credentials/.env`

### Load Credentials
```bash
source ~/.app_store_credentials/.env
echo "Key ID: $APP_STORE_CONNECT_KEY_ID"
echo "Issuer ID: $APP_STORE_CONNECT_ISSUER_ID"
echo "Key Path: $APP_STORE_CONNECT_KEY_PATH"
```

### Important: Use Python Instead of curl

**`curl` with single-quoted arguments often fails in Claude Code's bash tool due to shell quoting issues.** Always use `python3` with `requests` library for API calls. Generate JWT with PyJWT, then use `requests.get/post`.

### JWT Generation (Required for Every Request)

Apple uses JWT with ES256 signing. JWTs expire after 20 minutes.

**Generate JWT using Ruby (recommended):**
```bash
source ~/.app_store_credentials/.env

ruby -e '
require "jwt"
require "openssl"

key_file = ENV["APP_STORE_CONNECT_KEY_PATH"]
key_id = ENV["APP_STORE_CONNECT_KEY_ID"]
issuer_id = ENV["APP_STORE_CONNECT_ISSUER_ID"]

private_key = OpenSSL::PKey::EC.new(File.read(key_file))

payload = {
  iss: issuer_id,
  iat: Time.now.to_i,
  exp: Time.now.to_i + 20 * 60,  # 20 minutes
  aud: "appstoreconnect-v1"
}

token = JWT.encode(payload, private_key, "ES256", { kid: key_id })
puts token
'
```

**Generate JWT using Python:**
```bash
source ~/.app_store_credentials/.env

python3 << 'EOF'
import jwt
import time
import os

with open(os.environ["APP_STORE_CONNECT_KEY_PATH"], "r") as f:
    private_key = f.read()

payload = {
    "iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"],
    "iat": int(time.time()),
    "exp": int(time.time()) + 20 * 60,
    "aud": "appstoreconnect-v1"
}

token = jwt.encode(
    payload,
    private_key,
    algorithm="ES256",
    headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"]}
)
print(token)
EOF
```

**Store JWT for reuse:**
```bash
export ASC_TOKEN=$(python3 << 'EOF'
import jwt, time, os
with open(os.environ["APP_STORE_CONNECT_KEY_PATH"], "r") as f:
    private_key = f.read()
token = jwt.encode(
    {"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
    private_key, algorithm="ES256", headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"]}
)
print(token)
EOF
)
```

## API Endpoints

Base URL: `https://api.appstoreconnect.apple.com/v1`

### Request Format
```bash
curl -s 'https://api.appstoreconnect.apple.com/v1/{endpoint}' \
  -H "Authorization: Bearer $ASC_TOKEN" \
  -H "Content-Type: application/json"
```

---

## Known Apps

Track your team's apps here as you register them:

| Project | Bundle ID | App ID | Status |
|---------|-----------|--------|--------|
| `<YourApp>` | `com.example.yourapp` | `<numeric-app-id>` | Production / Prepare / Review |

> Tip: Use `bash scripts/audit-team-apps.sh` to auto-sync this table from App Store Connect API.

---

## macOS Platform Management

### Adding macOS Platform to an Existing iOS App

If the app's Bundle ID is registered as `UNIVERSAL`, you can add a macOS version directly via API:

```python
# Create a macOS App Store Version for an existing app
APP_ID = "<YOUR_APP_ID>"  # Your app ID

r = requests.post(f"{BASE}/appStoreVersions", headers=headers, json={
    "data": {
        "type": "appStoreVersions",
        "attributes": {
            "versionString": "1.0.0",
            "platform": "MAC_OS"
        },
        "relationships": {
            "app": {
                "data": {"type": "apps", "id": APP_ID}
            }
        }
    }
})
# Returns 201 with state: PREPARE_FOR_SUBMISSION
```

**Prerequisites:**
- Bundle ID must be `UNIVERSAL` platform (check via `GET /v1/bundleIds?filter[identifier]=...`)
- If Bundle ID is `IOS` only, you need to create a new Bundle ID or update it in the Developer Portal

**Check Bundle ID platform:**
```python
r = requests.get(f"{BASE}/bundleIds?filter[identifier]=com.example.app", headers=headers)
platform = r.json()["data"][0]["attributes"]["platform"]
# "UNIVERSAL" = iOS + macOS, "IOS" = iOS only, "MAC_OS" = macOS only
```

### Copying iOS Metadata to macOS Version

When adding macOS to an existing iOS app, you typically want the same metadata. Apple auto-creates empty localizations for the macOS version matching your iOS locales.

```python
IOS_VERSION_ID = "ios-version-id"
MACOS_VERSION_ID = "macos-version-id"

# 1. Get iOS localizations
r = requests.get(f"{BASE}/appStoreVersions/{IOS_VERSION_ID}/appStoreVersionLocalizations?limit=50", headers=headers)
ios_locs = r.json().get("data", [])

# 2. Get macOS localizations (auto-created, but empty)
r = requests.get(f"{BASE}/appStoreVersions/{MACOS_VERSION_ID}/appStoreVersionLocalizations?limit=50", headers=headers)
mac_locs = {loc["attributes"]["locale"]: loc["id"] for loc in r.json().get("data", [])}

# 3. PATCH each macOS localization with iOS data
for ios_loc in ios_locs:
    attrs = ios_loc["attributes"]
    locale = attrs["locale"]

    loc_attrs = {}
    for field in ["description", "keywords", "supportUrl", "marketingUrl", "promotionalText", "whatsNew"]:
        val = attrs.get(field)
        if val:
            loc_attrs[field] = val

    if not loc_attrs or locale not in mac_locs:
        continue

    requests.patch(f"{BASE}/appStoreVersionLocalizations/{mac_locs[locale]}", headers=headers, json={
        "data": {
            "type": "appStoreVersionLocalizations",
            "id": mac_locs[locale],
            "attributes": loc_attrs
        }
    })
```

### macOS Build + Sign + Upload (Flutter)

Flutter `build macos --release` produces ad-hoc signed apps. For Mac App Store, use `xcodebuild archive`:

```bash
# Step 1: xcodebuild archive (proper signing)
xcodebuild archive \
  -workspace macos/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -archivePath build/macos/App.xcarchive \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=<YOUR_TEAM_ID>

# Step 2: Export as pkg
xcodebuild -exportArchive \
  -archivePath build/macos/App.xcarchive \
  -exportPath build/macos/pkg \
  -exportOptionsPlist ExportOptions.plist

# Step 3: Upload (xcrun altool is fully deprecated since Nov 2023)
# Use Transporter CLI or fastlane instead:
/usr/bin/xcrun iTMSTransporter -m upload \
  -f build/macos/pkg/App.pkg \
  -apiKey "$API_KEY" \
  -apiIssuer "$API_ISSUER"
# Alternative: Use the Transporter app from Mac App Store (GUI)
```

**ExportOptions.plist for Mac App Store:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string><YOUR_TEAM_ID></string>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
```

**CocoaPods `set -u` Fix:** If `xcodebuild archive` fails with `source: unbound variable` in `Pods-Runner-frameworks.sh`, patch the `install_framework()` function to initialize `local source=""` before the if/elif chain. This is a known CocoaPods issue with `set -u`.

**Duplicate Certificate Fix:** If `codesign` shows `ambiguous (matches ... and ...)`, use the SHA-1 hash instead of the certificate name:
```bash
# Get SHA-1 hash of the first matching cert
CERT_HASH=$(security find-identity -v -p codesigning | grep "Apple Distribution.*($TEAM_ID)" | head -1 | awk '{print $2}')
codesign --force --sign "$CERT_HASH" --options runtime --entitlements "$ENT" "$APP"
```

**Required Certificates:**
- `Apple Distribution: <name> (<TEAM_ID>)` — signs the .app
- `3rd Party Mac Developer Installer: <name> (<TEAM_ID>)` — signs the .pkg

**Alternative: Manual Re-sign After Flutter Build:**
```bash
# If xcodebuild archive doesn't work, re-sign the flutter build output
APP="build/macos/Build/Products/Release/MyApp.app"
CERT="Apple Distribution: <Your Name> (<YOUR_TEAM_ID>)"
ENT="macos/Runner/Release.entitlements"

# Sign all embedded frameworks first
find "$APP/Contents/Frameworks" -name "*.framework" -exec \
  codesign --force --sign "$CERT" --entitlements "$ENT" {} \;

# Sign the main app
codesign --force --sign "$CERT" --entitlements "$ENT" "$APP"

# Create signed pkg
productbuild --component "$APP" /Applications \
  --sign "3rd Party Mac Developer Installer: <Your Name> (<YOUR_TEAM_ID>)" \
  build/macos/App.pkg
```

### Provisioning Profile Management via API

#### List Profiles for a Bundle ID
```python
# Get bundle ID record first
r = requests.get(f"{BASE}/bundleIds?filter[identifier]=com.example.app", headers=HEADERS)
bid = r.json()["data"][0]["id"]

# List profiles
r = requests.get(f"{BASE}/bundleIds/{bid}/profiles", headers=HEADERS)
for p in r.json()["data"]:
    print(f"{p['attributes']['name']} | {p['attributes']['profileType']} | {p['attributes']['profileState']}")
```

#### Create MAC_APP_STORE Profile
```python
import base64

# Get all distribution certificates
r = requests.get(f"{BASE}/certificates?filter[certificateType]=DISTRIBUTION", headers=HEADERS)
cert_ids = [c["id"] for c in r.json()["data"]]

# Create profile
r = requests.post(f"{BASE}/profiles", headers=HEADERS, json={
    "data": {
        "type": "profiles",
        "attributes": {
            "name": "Mac App Store com.example.app",
            "profileType": "MAC_APP_STORE"
        },
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bid}},
            "certificates": {"data": [{"type": "certificates", "id": cid} for cid in cert_ids]}
        }
    }
})

# Save profile content
profile = r.json()["data"]
profile_bytes = base64.b64decode(profile["attributes"]["profileContent"])
uuid = profile["attributes"]["uuid"]

# Save to Xcode profiles directory
with open(f"~/Library/Developer/Xcode/UserData/Provisioning Profiles/{uuid}.provisionprofile", "wb") as f:
    f.write(profile_bytes)
```

**Profile Types:**
| Type | Platform | Usage |
|------|----------|-------|
| `IOS_APP_STORE` | iOS | App Store distribution |
| `MAC_APP_STORE` | macOS | Mac App Store distribution |
| `IOS_APP_DEVELOPMENT` | iOS | Development/testing |
| `MAC_APP_DEVELOPMENT` | macOS | Development/testing |

**Important:** UNIVERSAL bundle IDs (supporting both iOS and macOS) need separate profiles for each platform type.

#### Mac App Store Entitlements (ITMS-90886 Fix)

When manually signing for Mac App Store, entitlements MUST include:
```xml
<key>com.apple.application-identifier</key>
<string>TEAM_ID.BUNDLE_ID</string>
<key>com.apple.developer.team-identifier</key>
<string>TEAM_ID</string>
```

Missing these causes ITMS-90886: "missing an application identifier" — upload succeeds but build is rejected for TestFlight.

---

## Common Operations

### 1. List All Apps
```bash
curl -s 'https://api.appstoreconnect.apple.com/v1/apps' \
  -H "Authorization: Bearer $ASC_TOKEN"
```

### 2. Get App Details
```bash
curl -s 'https://api.appstoreconnect.apple.com/v1/apps/{app_id}' \
  -H "Authorization: Bearer $ASC_TOKEN"
```

### 3. List In-App Purchases for App
```bash
curl -s 'https://api.appstoreconnect.apple.com/v1/apps/{app_id}/inAppPurchasesV2' \
  -H "Authorization: Bearer $ASC_TOKEN"
```

### 4. Create In-App Purchase

> **NOTE**: The v1 endpoint `POST /v1/inAppPurchases` returns `403 FORBIDDEN` for consumables.
> Use the **v2** endpoint instead: `POST /v2/inAppPurchases`.

```bash
curl -s -X POST 'https://api.appstoreconnect.apple.com/v2/inAppPurchases' \
  -H "Authorization: Bearer $ASC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "type": "inAppPurchases",
      "attributes": {
        "name": "Starter Pack - 80 Credits",
        "productId": "credits_starter_80",
        "inAppPurchaseType": "CONSUMABLE",
        "reviewNote": "80 credits for AI Agent usage"
      },
      "relationships": {
        "app": {
          "data": {
            "type": "apps",
            "id": "{app_id}"
          }
        }
      }
    }
  }'
```

### 5. Update In-App Purchase
```bash
curl -s -X PATCH 'https://api.appstoreconnect.apple.com/v1/inAppPurchases/{iap_id}' \
  -H "Authorization: Bearer $ASC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "type": "inAppPurchases",
      "id": "{iap_id}",
      "attributes": {
        "name": "Updated Name"
      }
    }
  }'
```

### 6. Delete In-App Purchase
```bash
curl -s -X DELETE 'https://api.appstoreconnect.apple.com/v1/inAppPurchases/{iap_id}' \
  -H "Authorization: Bearer $ASC_TOKEN"
```

### 7. List Subscription Groups
```bash
curl -s 'https://api.appstoreconnect.apple.com/v1/apps/{app_id}/subscriptionGroups' \
  -H "Authorization: Bearer $ASC_TOKEN"
```

### 8. Create Subscription Group
```bash
curl -s -X POST 'https://api.appstoreconnect.apple.com/v1/subscriptionGroups' \
  -H "Authorization: Bearer $ASC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "type": "subscriptionGroups",
      "attributes": {
        "referenceName": "Pro Subscriptions"
      },
      "relationships": {
        "app": {
          "data": {
            "type": "apps",
            "id": "{app_id}"
          }
        }
      }
    }
  }'
```

### 9. List Subscriptions in Group
```bash
curl -s 'https://api.appstoreconnect.apple.com/v1/subscriptionGroups/{group_id}/subscriptions' \
  -H "Authorization: Bearer $ASC_TOKEN"
```

---

## Complete IAP Product Configuration Guide

This section provides a complete workflow for configuring In-App Purchase products with pricing, localization, and availability.

### Overview of Configuration Steps

1. Get the IAP product ID from your app
2. Configure localization (display name, description)
3. Set availability (territories)
4. Configure pricing and price schedule
5. Verify configuration via API or web interface

### Step 1: Get IAP Product IDs

List all IAP products for an app to get their IDs:

```bash
APP_ID="<YOUR_APP_ID>"  # Your app ID

curl -s "https://api.appstoreconnect.apple.com/v1/apps/${APP_ID}/inAppPurchasesV2" \
  -H "Authorization: Bearer $ASC_TOKEN" | python3 -m json.tool
```

Example response structure:
```json
{
  "data": [
    {
      "id": "<YOUR_IAP_ID_MONTHLY>",
      "type": "inAppPurchases",
      "attributes": {
        "name": "月訂閱",
        "productId": "<your_product_id>",
        "inAppPurchaseType": "AUTOMATICALLY_RENEWABLE_SUBSCRIPTION"
      }
    }
  ]
}
```

### Step 2: Configure Localization

Create localization for an IAP product:

```bash
IAP_ID="<YOUR_IAP_ID>"  # Your IAP ID

curl -s -X POST "https://api.appstoreconnect.apple.com/v1/inAppPurchaseLocalizations" \
  -H "Authorization: Bearer $ASC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "type": "inAppPurchaseLocalizations",
      "attributes": {
        "locale": "zh-Hant",
        "name": "終身會員",
        "description": "一次付費永久使用,包含所有專業版功能"
      },
      "relationships": {
        "inAppPurchase": {
          "data": {
            "type": "inAppPurchases",
            "id": "'"${IAP_ID}"'"
          }
        }
      }
    }
  }'
```

**Important Notes:**
- Use `zh-Hant` for Traditional Chinese (not `zh-TW`)
- Use `zh-Hans` for Simplified Chinese
- Each locale requires separate localization creation
- Localization must be created before setting prices

### Step 3: Set Availability (Territories)

Configure which territories the IAP is available in:

```bash
IAP_ID="<YOUR_IAP_ID>"

curl -s -X POST "https://api.appstoreconnect.apple.com/v1/inAppPurchaseAvailabilities" \
  -H "Authorization: Bearer $ASC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "type": "inAppPurchaseAvailabilities",
      "attributes": {
        "availableInNewTerritories": true
      },
      "relationships": {
        "availableTerritories": {
          "data": [
            {"type": "territories", "id": "TWN"}
          ]
        },
        "inAppPurchase": {
          "data": {
            "type": "inAppPurchases",
            "id": "'"${IAP_ID}"'"
          }
        }
      }
    }
  }'
```

**Territory Codes:**
- `TWN` - Taiwan
- `USA` - United States
- `CHN` - China
- `JPN` - Japan
- etc.

### Step 4: Configure Pricing (The Complex Part)

#### 4.1 Understanding Price Points

Apple uses **Price Point IDs** which are Base64-encoded JSON strings:

```json
{
  "s": "IAP_PRODUCT_ID",
  "t": "TERRITORY_CODE",
  "p": "PRICE_TIER"
}
```

Example: `eyJzIjoiNjc1NjQ4MzMyOCIsInQiOiJUV04iLCJwIjoiMTAzNjMifQ`

Decodes to:
```json
{
  "s": "<YOUR_IAP_ID>",
  "t": "TWN",
  "p": "10363"
}
```

#### 4.2 Find Price Points for a Territory

**Method 1: Direct Query (Fast)**
```bash
IAP_ID="<YOUR_IAP_ID>"
TERRITORY="TWN"

curl -s "https://api.appstoreconnect.apple.com/v1/inAppPurchasePricePoints?filter[territory]=${TERRITORY}&filter[inAppPurchase]=${IAP_ID}&limit=200" \
  -H "Authorization: Bearer $ASC_TOKEN"
```

**Method 2: Pagination (For All Price Points)**
```python
import requests
import json
import os

ASC_TOKEN = os.environ['ASC_TOKEN']
IAP_ID = "<YOUR_IAP_ID>"
TERRITORY = "TWN"

url = f"https://api.appstoreconnect.apple.com/v1/inAppPurchasePricePoints"
headers = {
    "Authorization": f"Bearer {ASC_TOKEN}",
    "Content-Type": "application/json"
}

all_prices = []
params = {
    "filter[territory]": TERRITORY,
    "filter[inAppPurchase]": IAP_ID,
    "limit": 200
}

while True:
    response = requests.get(url, headers=headers, params=params)
    data = response.json()

    if 'data' in data:
        all_prices.extend(data['data'])

    # Check for next page
    if 'links' in data and 'next' in data['links']:
        url = data['links']['next']
        params = {}  # Next URL already includes params
    else:
        break

# Find specific price (e.g., NT$2990)
for price in all_prices:
    if 'customerPrice' in price['attributes']:
        customer_price = float(price['attributes']['customerPrice'])
        if abs(customer_price - 2990.0) < 0.01:
            print(f"Found NT$2990:")
            print(f"  Price Point ID: {price['id']}")
            print(f"  Tier: {price['attributes'].get('priceTier')}")
            break
```

#### 4.3 Common Taiwan Price Tiers

Based on actual API queries, here are commonly used Taiwan price tiers:

| Price (TWD) | Tier | Price Point ID (example) |
|------------|------|-------------------------|
| $30 | 10001 | eyJzIjoiNjc1NjQ4MzQwMCIsInQiOiJUV04iLCJwIjoiMTAwMDEifQ |
| $140 | 10039 | eyJzIjoiNjc1NjQ4MzQwMCIsInQiOiJUV04iLCJwIjoiMTAwMzkifQ |
| $990 | 10190 | eyJzIjoiNjc1NjQ4MzI3MiIsInQiOiJUV04iLCJwIjoiMTAxOTAifQ |
| $2,990 | 10363 | eyJzIjoiNjc1NjQ4MzMyOCIsInQiOiJUV04iLCJwIjoiMTAzNjMifQ |

**Note:** Price Point IDs include the IAP Product ID (`s` field), so they differ per product even for the same price tier.

#### 4.4 Create Price Schedule

Once you have the Price Point ID, create a price schedule:

```bash
IAP_ID="<YOUR_IAP_ID>"
PRICE_POINT_ID="eyJzIjoiNjc1NjQ4MzMyOCIsInQiOiJUV04iLCJwIjoiMTAzNjMifQ"

# Generate unique temporary ID for the price relationship
PRICE_TEMP_ID="price_$(date +%s)"

curl -s -X POST "https://api.appstoreconnect.apple.com/v1/inAppPurchasePriceSchedules" \
  -H "Authorization: Bearer $ASC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "type": "inAppPurchasePriceSchedules",
      "relationships": {
        "inAppPurchase": {
          "data": {
            "type": "inAppPurchases",
            "id": "'"${IAP_ID}"'"
          }
        },
        "manualPrices": {
          "data": [
            {
              "type": "inAppPurchasePrices",
              "id": "'"${PRICE_TEMP_ID}"'"
            }
          ]
        },
        "baseTerritory": {
          "data": {
            "type": "territories",
            "id": "TWN"
          }
        }
      }
    },
    "included": [
      {
        "type": "inAppPurchasePrices",
        "id": "'"${PRICE_TEMP_ID}"'",
        "relationships": {
          "inAppPurchasePricePoint": {
            "data": {
              "type": "inAppPurchasePricePoints",
              "id": "'"${PRICE_POINT_ID}"'"
            }
          }
        }
      }
    ]
  }' | python3 -m json.tool
```

**Key Points:**
- `baseTerritory`: The reference territory for pricing (usually your home market)
- `manualPrices`: Array of price relationships
- `included`: Contains the actual price point mapping
- Temporary ID in `manualPrices.data[].id` must match `included[].id`
- The API will automatically calculate equivalent prices for all other territories

#### 4.5 Verify Price Configuration

Check if price schedule was created successfully:

```bash
IAP_ID="<YOUR_IAP_ID>"

curl -s "https://api.appstoreconnect.apple.com/v1/inAppPurchases/${IAP_ID}/priceSchedule" \
  -H "Authorization: Bearer $ASC_TOKEN" | python3 -m json.tool
```

### Step 5: Complete Configuration Workflow

Here's a complete script that configures an IAP product from scratch:

```bash
#!/bin/bash
# Complete IAP Product Configuration Script

set -e  # Exit on error

# Load credentials
source ~/.app_store_credentials/.env

# Generate JWT
export ASC_TOKEN=$(python3 << 'EOF'
import jwt, time, os
with open(os.environ["APP_STORE_CONNECT_KEY_PATH"], "r") as f:
    private_key = f.read()
token = jwt.encode(
    {"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"],
     "iat": int(time.time()),
     "exp": int(time.time()) + 1200,
     "aud": "appstoreconnect-v1"},
    private_key,
    algorithm="ES256",
    headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"]}
)
print(token)
EOF
)

# Configuration
APP_ID="<YOUR_APP_ID>"
IAP_ID="<YOUR_IAP_ID>"
PRODUCT_NAME="終身會員"
PRODUCT_DESC="一次付費永久使用，包含所有專業版功能"
TARGET_PRICE=2990.0
BASE_TERRITORY="TWN"

echo "=== Configuring IAP Product: ${IAP_ID} ==="

# Step 1: Create Localization
echo "Step 1: Creating localization..."
curl -s -X POST "https://api.appstoreconnect.apple.com/v1/inAppPurchaseLocalizations" \
  -H "Authorization: Bearer $ASC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "type": "inAppPurchaseLocalizations",
      "attributes": {
        "locale": "zh-Hant",
        "name": "'"${PRODUCT_NAME}"'",
        "description": "'"${PRODUCT_DESC}"'"
      },
      "relationships": {
        "inAppPurchase": {
          "data": {"type": "inAppPurchases", "id": "'"${IAP_ID}"'"}
        }
      }
    }
  }' > /dev/null
echo "✓ Localization created"

# Step 2: Set Availability
echo "Step 2: Setting availability..."
curl -s -X POST "https://api.appstoreconnect.apple.com/v1/inAppPurchaseAvailabilities" \
  -H "Authorization: Bearer $ASC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "type": "inAppPurchaseAvailabilities",
      "attributes": {"availableInNewTerritories": true},
      "relationships": {
        "availableTerritories": {
          "data": [{"type": "territories", "id": "'"${BASE_TERRITORY}"'"}]
        },
        "inAppPurchase": {
          "data": {"type": "inAppPurchases", "id": "'"${IAP_ID}"'"}
        }
      }
    }
  }' > /dev/null
echo "✓ Availability set"

# Step 3: Find Price Point
echo "Step 3: Finding price point for NT\$${TARGET_PRICE}..."
PRICE_POINT_ID=$(python3 << EOF
import requests, json

url = "https://api.appstoreconnect.apple.com/v1/inAppPurchasePricePoints"
headers = {"Authorization": "Bearer ${ASC_TOKEN}"}
params = {
    "filter[territory]": "${BASE_TERRITORY}",
    "filter[inAppPurchase]": "${IAP_ID}",
    "limit": 200
}

all_prices = []
while True:
    r = requests.get(url, headers=headers, params=params)
    data = r.json()
    if 'data' in data:
        all_prices.extend(data['data'])
    if 'links' in data and 'next' in data['links']:
        url = data['links']['next']
        params = {}
    else:
        break

for price in all_prices:
    if 'customerPrice' in price['attributes']:
        if abs(float(price['attributes']['customerPrice']) - ${TARGET_PRICE}) < 0.01:
            print(price['id'])
            break
EOF
)

if [ -z "$PRICE_POINT_ID" ]; then
    echo "✗ Price point not found for NT\$${TARGET_PRICE}"
    exit 1
fi
echo "✓ Found price point: ${PRICE_POINT_ID}"

# Step 4: Create Price Schedule
echo "Step 4: Creating price schedule..."
PRICE_TEMP_ID="price_$(date +%s)"
curl -s -X POST "https://api.appstoreconnect.apple.com/v1/inAppPurchasePriceSchedules" \
  -H "Authorization: Bearer $ASC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "type": "inAppPurchasePriceSchedules",
      "relationships": {
        "inAppPurchase": {"data": {"type": "inAppPurchases", "id": "'"${IAP_ID}"'"}},
        "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "'"${PRICE_TEMP_ID}"'"}]},
        "baseTerritory": {"data": {"type": "territories", "id": "'"${BASE_TERRITORY}"'"}}
      }
    },
    "included": [{
      "type": "inAppPurchasePrices",
      "id": "'"${PRICE_TEMP_ID}"'",
      "relationships": {
        "inAppPurchasePricePoint": {
          "data": {"type": "inAppPurchasePricePoints", "id": "'"${PRICE_POINT_ID}"'"}
        }
      }
    }]
  }' > /dev/null
echo "✓ Price schedule created"

echo ""
echo "=== Configuration Complete ==="
echo "Product: ${PRODUCT_NAME}"
echo "Price: NT\$${TARGET_PRICE}"
echo "Base Territory: ${BASE_TERRITORY}"
```

### Troubleshooting Common Issues

#### Issue 1: 409 Conflict - Localization Already Exists
**Error:**
```json
{
  "errors": [{
    "status": "409",
    "code": "ENTITY_ALREADY_EXISTS"
  }]
}
```

**Solution:** Update existing localization instead of creating new one.

#### Issue 2: 404 Not Found - Invalid IAP ID
**Error:**
```json
{
  "errors": [{
    "status": "404",
    "code": "NOT_FOUND"
  }]
}
```

**Solution:** Verify IAP ID by listing all IAPs for your app first.

#### Issue 3: Products Show "MISSING_METADATA" Status

Even after API configuration, products may show "缺少元資料" (Missing Metadata) in App Store Connect.

**Possible causes:**
1. Missing review screenshot (must upload via web interface)
2. Missing app binary submission
3. Configuration not yet synced

**Solution:**
- Upload review screenshot via App Store Connect web interface
- First IAP must be submitted with app binary
- Wait a few minutes for API changes to sync
- Verify via Playwright or web browser that prices are actually set
- **Missing pricing** is the most common cause — localizations alone won't clear MISSING_METADATA

#### Issue 4: JWT Authentication Failures

**Error:**
```json
{
  "errors": [{
    "status": "401",
    "code": "NOT_AUTHORIZED"
  }]
}
```

**Solution:**
- Use Python with PyJWT library (more reliable than bash/OpenSSL)
- Ensure JWT hasn't expired (20 minute limit)
- Verify all three credentials are correct (Key ID, Issuer ID, Private Key)
- Check that private key file has correct permissions

#### Issue 5: Age Rating Declaration — Mixed Attribute Types

**Error:**
```
Unexpected json type for 'healthOrWellnessTopics'. Expected BOOLEAN but got STRING
You must provide a value for the attribute 'gunsOrOtherWeapons'
```

**Explanation:** Age rating attributes use TWO different types:

| Type | Attributes |
|------|-----------|
| **String enum** (`NONE` / `INFREQUENT_OR_MILD` / `FREQUENT_OR_INTENSE`) | `alcoholTobaccoOrDrugUseOrReferences`, `contests`, `gamblingSimulated`, `gunsOrOtherWeapons`, `horrorOrFearThemes`, `matureOrSuggestiveThemes`, `medicalOrTreatmentInformation`, `profanityOrCrudeHumor`, `sexualContentGraphicAndNudity`, `sexualContentOrNudity`, `violenceCartoonOrFantasy`, `violenceRealistic`, `violenceRealisticProlongedGraphicOrSadistic` |
| **Boolean** (`true` / `false`) | `gambling`, `unrestrictedWebAccess`, `lootBox`, `advertising`, `messagingAndChat`, `userGeneratedContent`, `parentalControls`, `ageAssurance`, `healthOrWellnessTopics` |

**Solution:** You MUST provide ALL attributes in a single PATCH call — the API requires them all at once and will reject partial updates. The fields `kidsAgeBand` and `developerAgeRatingInfoUrl` are optional and will remain `None`.

#### Issue 6: IAP/Subscription Description Character Limit

**Error:**
```json
{"code": "ENTITY_ERROR.ATTRIBUTE.INVALID.TOO_LONG"}
```

**Solution:** IAP and subscription localization `description` has a strict character limit (~45 characters). European language descriptions tend to be longer than CJK equivalents. Keep descriptions very short (e.g., "Ad-free, all features, forever" instead of "One-time purchase for lifetime ad-free experience and all premium features").

#### Issue 7: V1 vs V2 Endpoint for IAP Localizations

**Error:**
```json
{"code": "PATH_ERROR", "detail": "The relationship 'inAppPurchaseLocalizations' does not exist"}
```

**Explanation:** When creating IAP localizations, the `POST` creates via V1, but listing them requires the **V2** endpoint:
- ❌ `GET /v1/inAppPurchases/{id}/inAppPurchaseLocalizations` → 404 PATH_ERROR
- ✅ `GET /v2/inAppPurchases/{id}/inAppPurchaseLocalizations` → 200 OK

**Solution:** Always use the V2 endpoint to list/verify IAP localizations:
```python
r = requests.get(f"https://api.appstoreconnect.apple.com/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations", headers=HEADERS)
```

#### Issue 8: Inline Entity ID Format for Price Schedules

**Error:**
```json
{"code": "ENTITY_ERROR.INCLUDED.INVALID_ID", "detail": "The provided included entity id has invalid format. For inline creation..."}
```

**Solution:** When creating `inAppPurchasePriceSchedules` with inline `inAppPurchasePrices`, the temporary ID must use `${uuid}` format:
```python
import uuid
temp_id = "${" + str(uuid.uuid4()) + "}"
# Use this temp_id in both data.relationships.manualPrices[].id and included[].id
```

#### Issue 9: IAP Price Points — V2 Endpoint Required

**Error:**
```json
{"code": "FORBIDDEN_ERROR", "detail": "The resource 'inAppPurchasePricePoints' has no allowed operations"}
```

**Explanation:** Finding price points for IAP and subscriptions requires different endpoints:
- **IAP Non-Consumable**: `GET /v2/inAppPurchases/{id}/pricePoints?filter[territory]=TWN` (NOT v1)
- **Subscriptions**: `GET /v1/subscriptions/{id}/pricePoints?filter[territory]=TWN`
- ❌ `GET /v1/inAppPurchasePricePoints` → 403 FORBIDDEN
- ❌ `GET /v1/subscriptionPricePoints` → 403 FORBIDDEN (only GET_INSTANCE allowed, not collection)

**Tip:** Price point lists are very long (~800 items). Use `limit=200` and paginate to find your target price.

#### Issue 10: Release Notes (What's New) Emoji Rejection

**Error:**
```json
{
  "code": "ENTITY_ERROR.ATTRIBUTE.INVALID",
  "detail": "An attribute value has invalid characters. - What's New in This Version can’t contain the following character(s): 🧹, 🖼, 🛠, ️"
}
```

**Explanation:** Apple's App Store Connect API strictly rejects many unicode emojis and variation selectors in the `release_notes.txt` (What's New in This Version) when uploading metadata via Fastlane or API. This usually happens when the same emoji-filled text works perfectly fine for Google Play, but Apple rejects it. Common culprits include: 🔗, 💬, 🌍, 🧹, 🖼, 🛠, ⚡️, ✨, 🚀, 🐛, 🎨, ⚙️, 💡, 📍.

**Solution:**
When uploading App Store metadata with `fastlane deliver`, you must strip emojis from the `release_notes.txt` of **all locales**. Do not just remove the specific ones in the error message, as there might be others it will reject on the next try.

Here is a Python script to quickly clean release notes in a fastlane project:

```python
import glob
import re

files = glob.glob('ios/fastlane/metadata/*/release_notes.txt')
for fpath in files:
    with open(fpath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Remove common emojis and the invisible variation selector (\ufe0f)
    cleaned = re.sub(r'[🔗💬🌍🧹🖼🛠⚡✨🚀🐛🎨⚙💡📍]', '', content)
    cleaned = cleaned.replace('\ufe0f', '')
    
    if cleaned != content:
        with open(fpath, 'w', encoding='utf-8') as f:
            f.write(cleaned)
        print(f"Cleaned {fpath}")
```

### Example: App Configuration

Here's an example configuration for an app with multiple subscription tiers:

```bash
# App ID: <YOUR_APP_ID>
# Bundle ID: com.example.yourapp

# Products configured:
# 1. Monthly Subscription (<YOUR_IAP_ID_MONTHLY>): NT$140 (tier 10039)
# 2. Yearly Subscription (<YOUR_IAP_ID_YEARLY>): NT$990 (tier 10190)
# 3. Lifetime Membership (<YOUR_IAP_ID>): NT$2990 (tier 10363)

# All products:
# - Localized in zh-Hant (Traditional Chinese)
# - Available in Taiwan (TWN) as base territory
# - Prices automatically calculated for 175 territories
# - RevenueCat entitlement: "premium"
```


---

## App Store Server API (Purchase Validation)

Different from App Store Connect API. Used for transaction validation.

Base URL: `https://api.storekit.itunes.apple.com/inApps/v1`

### Validate Transaction
```bash
curl -s 'https://api.storekit.itunes.apple.com/inApps/v1/transactions/{transactionId}' \
  -H "Authorization: Bearer $ASC_TOKEN"
```

### Get Subscription Status
```bash
curl -s 'https://api.storekit.itunes.apple.com/inApps/v1/subscriptions/{transactionId}' \
  -H "Authorization: Bearer $ASC_TOKEN"
```

### Get Transaction History
```bash
curl -s 'https://api.storekit.itunes.apple.com/inApps/v1/history/{transactionId}' \
  -H "Authorization: Bearer $ASC_TOKEN"
```

---

## Auto-Renewable Subscriptions Complete Guide

This section covers the specific APIs for managing auto-renewable subscriptions, which differ from regular IAP products.

### Subscription State Values

| State | Description |
|-------|-------------|
| `MISSING_METADATA` | Incomplete configuration - check localization, availability, prices |
| `READY_TO_SUBMIT` | Fully configured, can be submitted with app |
| `WAITING_FOR_REVIEW` | Submitted, pending Apple review |
| `APPROVED` | Approved and live |
| `DEVELOPER_REMOVED_FROM_SALE` | Removed by developer |

**IMPORTANT**: Subscriptions remain in `MISSING_METADATA` until the app binary is first submitted. This is expected behavior - they are still usable in sandbox testing.

### 1. Subscription Localizations

**Create Subscription Localization:**
```python
# Critical: Must match app's primary locale!
data = {
    "data": {
        "type": "subscriptionLocalizations",
        "attributes": {
            "locale": "zh-Hant",  # Use zh-Hant, NOT zh-TW!
            "name": "專業版 (月付)",
            "description": "每月訂閱，享有無限功能"  # Max 55 characters!
        },
        "relationships": {
            "subscription": {
                "data": {"type": "subscriptions", "id": "{subscription_id}"}
            }
        }
    }
}
resp = requests.post(f"{BASE_URL}/subscriptionLocalizations", headers=headers, json=data)
```

**Important Notes:**
- Description has **55 character limit**
- Must create localization for app's **primary locale** (check `apps/{id}` → `primaryLocale`)
- Common locales: `en-US`, `zh-Hant` (Traditional Chinese), `zh-Hans` (Simplified Chinese)

### 2. Subscription Availability

**Create Availability for All Territories:**
```python
# First get all territories
resp = requests.get(f"{BASE_URL}/territories?limit=200", headers=headers)
territories = resp.json().get("data", [])
territory_data = [{"type": "territories", "id": t["id"]} for t in territories]

# Create availability
data = {
    "data": {
        "type": "subscriptionAvailabilities",
        "attributes": {
            "availableInNewTerritories": True
        },
        "relationships": {
            "subscription": {
                "data": {"type": "subscriptions", "id": "{subscription_id}"}
            },
            "availableTerritories": {
                "data": territory_data  # Array of all territories
            }
        }
    }
}
resp = requests.post(f"{BASE_URL}/subscriptionAvailabilities", headers=headers, json=data)
```

### 3. Subscription Group Localizations

**Create Group Localization:**
```python
data = {
    "data": {
        "type": "subscriptionGroupLocalizations",
        "attributes": {
            "locale": "zh-Hant",
            "name": "專業版訂閱"
        },
        "relationships": {
            "subscriptionGroup": {
                "data": {"type": "subscriptionGroups", "id": "{group_id}"}
            }
        }
    }
}
resp = requests.post(f"{BASE_URL}/subscriptionGroupLocalizations", headers=headers, json=data)
```

### 4. Subscription Pricing

> [!CAUTION]
> **NEVER SKIP THIS STEP.** NEVER tell the user "pricing needs to be done manually on the web."
> The complete working API method (PATCH + equalizations) is documented below. USE IT.
> This is the #1 most commonly skipped step — do NOT repeat this mistake.

> **IMPORTANT**: `POST /v1/subscriptionPrices` returns `500 UNEXPECTED_ERROR` when creating
> initial subscription prices. Use the **PATCH + equalizations** approach below instead.

**Complete Subscription Pricing (PATCH + Equalizations — Working Method):**

```python
import requests, json

def set_subscription_price(sub_id, target_usd, headers):
    """Set subscription price for all territories using PATCH + equalizations.
    
    This is the ONLY reliable method. POST /subscriptionPrices returns 500 for initial prices.
    
    Steps:
    1. Find the price point ID for the target USD price
    2. Get equalized price points for all other territories
    3. PATCH the subscription with inline prices for all territories
    """
    BASE_URL = "https://api.appstoreconnect.apple.com/v1"
    
    # Step 1: Find USA price point for target price (paginate — Apple has 400+ tiers)
    all_points = []
    url = f"{BASE_URL}/subscriptions/{sub_id}/pricePoints"
    params = {"filter[territory]": "USA", "limit": 200}
    while url:
        resp = requests.get(url, headers=headers, params=params)
        data = resp.json()
        all_points.extend(data.get("data", []))
        next_url = data.get("links", {}).get("next")
        if next_url and next_url != url:
            url = next_url
            params = {}
        else:
            break

    base_pp_id = None
    for pt in all_points:
        cp = float(pt["attributes"].get("customerPrice", 0))
        if abs(cp - target_usd) < 0.01:
            base_pp_id = pt["id"]
            break

    if not base_pp_id:
        raise ValueError(f"No price point found for ${target_usd}")

    # Step 2: Get equalizations (Apple auto-calculates equivalent prices for all territories)
    eq_prices = []
    url = f"{BASE_URL}/subscriptionPricePoints/{base_pp_id}/equalizations"
    params = {"limit": 200}
    while url:
        resp = requests.get(url, headers=headers, params=params)
        data = resp.json()
        eq_prices.extend(data.get("data", []))
        next_url = data.get("links", {}).get("next")
        if next_url and next_url != url:
            url = next_url
            params = {}
        else:
            break

    # Step 3: Build inline prices and PATCH the subscription
    included = []
    price_refs = []

    # Add base territory (USA)
    lid = "${priceBase}"
    price_refs.append({"type": "subscriptionPrices", "id": lid})
    included.append({
        "type": "subscriptionPrices",
        "id": lid,
        "attributes": {"startDate": None, "preserveCurrentPrice": False},
        "relationships": {
            "subscriptionPricePoint": {
                "data": {"type": "subscriptionPricePoints", "id": base_pp_id}
            }
        }
    })

    # Add all equalized territories
    for i, eq in enumerate(eq_prices):
        lid = f"${{price{i}}}"
        price_refs.append({"type": "subscriptionPrices", "id": lid})
        included.append({
            "type": "subscriptionPrices",
            "id": lid,
            "attributes": {"startDate": None, "preserveCurrentPrice": False},
            "relationships": {
                "subscriptionPricePoint": {
                    "data": {"type": "subscriptionPricePoints", "id": eq["id"]}
                }
            }
        })

    # PATCH the subscription with all inline prices
    resp = requests.patch(
        f"{BASE_URL}/subscriptions/{sub_id}",
        headers=headers,
        json={
            "data": {
                "type": "subscriptions",
                "id": sub_id,
                "relationships": {
                    "prices": {"data": price_refs}
                }
            },
            "included": included
        }
    )

    if resp.status_code in [200, 201, 204]:
        return True
    else:
        raise Exception(f"Failed: {resp.json().get('errors', [{}])[0]}")
```

**Key Points:**
- Inline price IDs must use `${...}` format (e.g., `${priceBase}`, `${price0}`)
- Equalizations typically return ~174 territory prices; combined with base = ~175 territories
- `startDate: null` means "effective immediately"
- `preserveCurrentPrice: false` for new subscriptions (no existing subscribers)

**Check Existing Prices:**
```python
resp = requests.get(
    f"{BASE_URL}/subscriptions/{sub_id}/prices?filter[territory]=USA&include=subscriptionPricePoint",
    headers=headers
)
```

### 4b. Update Pricing for APPROVED Subscriptions (Price Change)

> **CRITICAL**: The PATCH + equalizations method above ONLY works for subscriptions that have **never had pricing set**.
> For already-approved subscriptions with existing prices, you will get:
> `409: Initial price cannot be created again after subscription is approved.`
>
> You must **schedule a future price change** instead.

**Working method for approved subscriptions:**

```python
from datetime import datetime, timedelta, timezone

def change_approved_subscription_price(sub_id, target_usd, headers):
    """Change price for an already-approved subscription.
    
    For APPROVED subscriptions, you CANNOT:
    - POST /subscriptionPrices with startDate=null (409 error)
    - DELETE existing prices (409 - only future prices can be deleted)
    - PATCH individual price entries
    
    You MUST use PATCH /subscriptions/{id} with startDate = future date.
    """
    BASE_URL = "https://api.appstoreconnect.apple.com/v1"
    
    # Step 1: Find price point for target USD
    all_points = []
    url = f"{BASE_URL}/subscriptions/{sub_id}/pricePoints"
    params = {"filter[territory]": "USA", "limit": 200}
    while url:
        resp = requests.get(url, headers=headers, params=params)
        data = resp.json()
        all_points.extend(data.get("data", []))
        next_url = data.get("links", {}).get("next")
        if next_url and next_url != url:
            url = next_url
            params = {}
        else:
            break

    base_pp_id = None
    for pt in all_points:
        cp = float(pt["attributes"].get("customerPrice", 0))
        if abs(cp - target_usd) < 0.01:
            base_pp_id = pt["id"]
            break
    if not base_pp_id:
        raise ValueError(f"No price point for ${target_usd}")

    # Step 2: Get equalizations
    eq_prices = []
    url = f"{BASE_URL}/subscriptionPricePoints/{base_pp_id}/equalizations"
    params = {"limit": 200}
    while url:
        resp = requests.get(url, headers=headers, params=params)
        data = resp.json()
        eq_prices.extend(data.get("data", []))
        next_url = data.get("links", {}).get("next")
        if next_url and next_url != url:
            url = next_url
            params = {}
        else:
            break

    # Step 3: Schedule price change for TOMORROW (earliest possible)
    tomorrow = (datetime.now(timezone.utc) + timedelta(days=1)).strftime("%Y-%m-%d")
    
    included = []
    price_refs = []

    # Base territory (USA)
    lid = "${priceBase}"
    price_refs.append({"type": "subscriptionPrices", "id": lid})
    included.append({
        "type": "subscriptionPrices",
        "id": lid,
        "attributes": {"startDate": tomorrow, "preserveCurrentPrice": False},
        "relationships": {
            "subscriptionPricePoint": {
                "data": {"type": "subscriptionPricePoints", "id": base_pp_id}
            }
        }
    })

    for i, eq in enumerate(eq_prices):
        lid = f"${{price{i}}}"
        price_refs.append({"type": "subscriptionPrices", "id": lid})
        included.append({
            "type": "subscriptionPrices",
            "id": lid,
            "attributes": {"startDate": tomorrow, "preserveCurrentPrice": False},
            "relationships": {
                "subscriptionPricePoint": {
                    "data": {"type": "subscriptionPricePoints", "id": eq["id"]}
                }
            }
        })

    # PATCH subscription with scheduled prices
    resp = requests.patch(
        f"{BASE_URL}/subscriptions/{sub_id}",
        headers=headers,
        json={
            "data": {
                "type": "subscriptions",
                "id": sub_id,
                "relationships": {
                    "prices": {"data": price_refs}
                }
            },
            "included": included
        }
    )
    
    if resp.status_code in [200, 201, 204]:
        return tomorrow
    else:
        raise Exception(f"Failed: {resp.json().get('errors', [{}])[0]}")
```

**Key differences from initial pricing:**
- `startDate` must be a **future date** (e.g., tomorrow `YYYY-MM-DD`), NOT `null`
- `preserveCurrentPrice: False` means existing subscribers get the new price at their next renewal
- Set `preserveCurrentPrice: True` to grandfather existing subscribers at the old price
```

### 4c. Subscription Introductory Offers (Free Trials)

> **IMPORTANT**: Apple stores intro offers **per-territory** (one record per country).
> A "175 territories" intro offer = 175 individual API records.
> There is NO bulk create/delete — you must iterate over all territories.

**List Introductory Offers for a Subscription:**
```python
# Returns paginated results (use limit=200 for max per page)
resp = requests.get(
    f"{BASE_URL}/subscriptions/{sub_id}/introductoryOffers?limit=200",
    headers=headers
)
offers = resp.json().get("data", [])
# Each offer has: id, attributes.offerMode (FREE_TRIAL/PAY_AS_YOU_GO/PAY_UP_FRONT), attributes.duration (THREE_DAYS/ONE_WEEK/etc.)
```

**Create Introductory Offer (per territory):**
```python
data = {
    "data": {
        "type": "subscriptionIntroductoryOffers",
        "attributes": {
            "duration": "THREE_DAYS",      # THREE_DAYS, ONE_WEEK, TWO_WEEKS, ONE_MONTH, TWO_MONTHS, THREE_MONTHS, SIX_MONTHS, ONE_YEAR
            "offerMode": "FREE_TRIAL",     # FREE_TRIAL, PAY_AS_YOU_GO, PAY_UP_FRONT
            "numberOfPeriods": 1,
            "startDate": None,             # null = effective immediately
            "endDate": None                # null = no end date
        },
        "relationships": {
            "subscription": {
                "data": {"type": "subscriptions", "id": "{subscription_id}"}
            },
            "territory": {
                "data": {"type": "territories", "id": "USA"}  # ISO 3166-1 alpha-3
            }
        }
    }
}
resp = requests.post(f"{BASE_URL}/subscriptionIntroductoryOffers", headers=headers, json=data)
```

**Delete Introductory Offer:**
```python
# Delete a single territory's intro offer by its offer ID
resp = requests.delete(f"{BASE_URL}/subscriptionIntroductoryOffers/{offer_id}", headers=headers)
# Returns 204 No Content on success
```

**Batch Delete All Intro Offers for a Subscription:**
```python
def remove_all_intro_offers(sub_id, headers):
    """Remove ALL introductory offers from a subscription (all territories)."""
    all_offers = []
    url = f"{BASE_URL}/subscriptions/{sub_id}/introductoryOffers?limit=200"
    while url:
        r = requests.get(url, headers=headers)
        data = r.json()
        all_offers.extend(data.get("data", []))
        url = data.get("links", {}).get("next")
    
    deleted = 0
    for o in all_offers:
        r = requests.delete(f"{BASE_URL}/subscriptionIntroductoryOffers/{o['id']}", headers=headers)
        if r.status_code == 204:
            deleted += 1
    
    return deleted  # Should equal len(all_offers)
```

**Best Practice (Yearly-Only Trial):**
- Only attach free trials to **yearly** subscriptions to maximize LTV
- Monthly subscriptions should NOT have free trials (users would trial → cancel after 1 month)
- Industry standard: Spotify, YouTube Premium, Notion all use yearly-only trials

### 5. Add Review Note

```python
data = {
    "data": {
        "type": "subscriptions",
        "id": "{subscription_id}",
        "attributes": {
            "reviewNote": "Unlocks premium features and unlimited AI access"
        }
    }
}
resp = requests.patch(f"{BASE_URL}/subscriptions/{subscription_id}", headers=headers, json=data)
```

### 6. Complete Configuration Checklist

To move from `MISSING_METADATA` to `READY_TO_SUBMIT`:

1. ✅ **Subscription Localization** - Must include app's primary locale
2. ✅ **Subscription Group Localization** - Same locale as above
3. ✅ **Subscription Availability** - Enable territories
4. ✅ **Subscription Prices** - Set for at least one territory
5. ✅ **Review Note** - Optional but recommended
6. ⚠️ **App Binary** - First submission required for READY_TO_SUBMIT

### 7. Troubleshooting MISSING_METADATA

If subscription still shows MISSING_METADATA after API configuration:

1. **Check App Primary Locale:**
   ```python
   resp = requests.get(f"{BASE_URL}/apps/{app_id}", headers=headers)
   print(resp.json()["data"]["attributes"]["primaryLocale"])
   ```
   
2. **Verify Localization Exists for Primary Locale:**
   ```python
   resp = requests.get(f"{BASE_URL}/subscriptions/{sub_id}/subscriptionLocalizations", headers=headers)
   ```

3. **Check Availability:**
   ```python
   resp = requests.get(f"{BASE_URL}/subscriptions/{sub_id}/subscriptionAvailability", headers=headers)
   # 404 means no availability configured
   ```

4. **Verify Price Points:**
   ```python
   resp = requests.get(f"{BASE_URL}/subscriptions/{sub_id}/prices?limit=200", headers=headers)
   print(f"Prices configured: {len(resp.json().get('data', []))}")
   ```

5. **Check App Store Version:**
   ```python
   resp = requests.get(f"{BASE_URL}/apps/{app_id}/appStoreVersions", headers=headers)
   # If "PREPARE_FOR_SUBMISSION", subscriptions will remain MISSING_METADATA
   # This is expected - submit app first
   ```

### Common Price Tiers (USD)

| Price | Tier |
|-------|------|
| $0.99 | 10010 |
| $1.99 | 10022 |
| $2.99 | 10033 |
| $4.99 | 10062 |
| $9.99 | 10127 |
| $19.99 | 10199 |
| $29.99 | 10227 |
| $34.99 | 10252 |
| $49.99 | 10308 |
| $59.99 | 10357 |
| $99.99 | 10449 |
| $119.99 | 10500 |
| $279.99 | 10616 |
| $469.99 | 10679 |
| $949.99 | 10788 |

**Note:** Price tiers go up to 800+ options. Use pagination to find exact prices.

### IAP Price Schedule — `${local-id}` Format

When creating IAP price schedules via `inAppPurchasePriceSchedules`, the inline entity IDs
**must** use the `${...}` format:

```python
temp_id = "${price1}"  # MUST use ${...} format!
resp = requests.post(f"{BASE_URL}/inAppPurchasePriceSchedules", headers=headers, json={
    "data": {
        "type": "inAppPurchasePriceSchedules",
        "relationships": {
            "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
            "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": temp_id}]},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}}
        }
    },
    "included": [{
        "type": "inAppPurchasePrices",
        "id": temp_id,
        "relationships": {
            "inAppPurchasePricePoint": {
                "data": {"type": "inAppPurchasePricePoints", "id": price_point_id}
            }
        }
    }]
})
```

> **IMPORTANT**: Using formats like `price_123456` will return
> `ENTITY_ERROR.INCLUDED.INVALID_ID`. Always use `${...}` format.

---

## TestFlight Management

### List Beta Testers
```bash
curl -s 'https://api.appstoreconnect.apple.com/v1/betaTesters' \
  -H "Authorization: Bearer $ASC_TOKEN"
```

### Add Beta Tester
```bash
curl -s -X POST 'https://api.appstoreconnect.apple.com/v1/betaTesters' \
  -H "Authorization: Bearer $ASC_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "type": "betaTesters",
      "attributes": {
        "email": "tester@example.com",
        "firstName": "Test",
        "lastName": "User"
      },
      "relationships": {
        "betaGroups": {
          "data": [{"type": "betaGroups", "id": "{group_id}"}]
        }
      }
    }
  }'
```

### List Builds
```bash
curl -s 'https://api.appstoreconnect.apple.com/v1/builds?filter[app]={app_id}' \
  -H "Authorization: Bearer $ASC_TOKEN"
```

---

## Rate Limits

| Limit | Value |
|-------|-------|
| Hourly | 3,600 requests/hour |
| Per-Minute | ~300 requests (undocumented) |
| Response | HTTP 429 when exceeded |

### Rate Limit Headers
- `X-RateLimit-Limit`: Total limit
- `X-RateLimit-Remaining`: Remaining requests
- `Retry-After`: Wait time (on 429)

---

## Error Handling

### Common Errors

| Code | Meaning | Solution |
|------|---------|----------|
| 401 | Unauthorized | JWT expired or invalid - regenerate |
| 403 | Forbidden | Insufficient permissions for API key |
| 404 | Not Found | Resource doesn't exist |
| 409 | Conflict | Resource already exists |
| 429 | Rate Limited | Wait and retry |

### Error Response Format
```json
{
  "errors": [
    {
      "id": "error-id",
      "status": "401",
      "code": "NOT_AUTHORIZED",
      "title": "Authentication credentials are missing or invalid",
      "detail": "Provide a properly configured and signed bearer token..."
    }
  ]
}
```

---

## In-App Purchase Types

| Type | Description |
|------|-------------|
| `CONSUMABLE` | One-time purchase, can buy multiple times |
| `NON_CONSUMABLE` | One-time purchase, permanent |
| `NON_RENEWING_SUBSCRIPTION` | Subscription without auto-renewal |
| `AUTOMATICALLY_RENEWABLE_SUBSCRIPTION` | Auto-renewing subscription |

---

## Quick Setup Script

```bash
#!/bin/bash
# Generate JWT and test API connection

source ~/.app_store_credentials/.env

# Check if jwt package is installed
python3 -c "import jwt" 2>/dev/null || pip3 install pyjwt

# Generate JWT
export ASC_TOKEN=$(python3 << 'EOF'
import jwt, time, os
with open(os.environ["APP_STORE_CONNECT_KEY_PATH"], "r") as f:
    private_key = f.read()
token = jwt.encode(
    {"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
    private_key, algorithm="ES256", headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"]}
)
print(token)
EOF
)

echo "Token generated successfully!"
echo ""
echo "Testing API connection..."
curl -s 'https://api.appstoreconnect.apple.com/v1/apps' \
  -H "Authorization: Bearer $ASC_TOKEN" | python3 -m json.tool | head -20
```

---

## RevenueCat Integration (REST API v2)

App Store Connect 的憑證可以用於 RevenueCat 建立 iOS App。

### RevenueCat 所需憑證對照

| RevenueCat 參數 | App Store Connect 來源 |
|----------------|----------------------|
| `subscription_key_id` | `$APP_STORE_CONNECT_KEY_ID` |
| `subscription_key_issuer` | `$APP_STORE_CONNECT_ISSUER_ID` |
| `subscription_private_key` | `AuthKey_*.p8` 檔案內容 |
| `shared_secret` | 需從各 App 的 IAP 設定取得 |

### 使用 App Store Connect 憑證建立 RevenueCat iOS App

```bash
# 載入憑證
source ~/.app_store_credentials/.env

# 讀取私鑰
PRIVATE_KEY=$(cat $APP_STORE_CONNECT_KEY_PATH)

# 建立 RevenueCat iOS App
curl -X POST "https://api.revenuecat.com/v2/projects/{project_id}/apps" \
  -H "Authorization: Bearer {REVENUECAT_SECRET_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "My iOS App",
    "type": "app_store",
    "app_store": {
      "bundle_id": "com.example.myapp",
      "shared_secret": "YOUR_APP_SHARED_SECRET",
      "subscription_private_key": "'"$PRIVATE_KEY"'",
      "subscription_key_id": "'"$APP_STORE_CONNECT_KEY_ID"'",
      "subscription_key_issuer": "'"$APP_STORE_CONNECT_ISSUER_ID"'"
    }
  }'
```

### RevenueCat REST API v2 常用端點

Base URL: `https://api.revenuecat.com/v2`

#### 列出專案中的 Apps
```bash
curl -s "https://api.revenuecat.com/v2/projects/{project_id}/apps" \
  -H "Authorization: Bearer {SECRET_KEY}"
```

#### 建立產品
```bash
curl -X POST "https://api.revenuecat.com/v2/projects/{project_id}/products" \
  -H "Authorization: Bearer {SECRET_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "store_identifier": "product_id",
    "app_id": "app1a2b3c4",
    "type": "subscription",
    "display_name": "Monthly Subscription"
  }'
```

#### 列出 Entitlements
```bash
curl -s "https://api.revenuecat.com/v2/projects/{project_id}/entitlements" \
  -H "Authorization: Bearer {SECRET_KEY}"
```

#### 將產品附加到 Entitlement
```bash
curl -X POST "https://api.revenuecat.com/v2/projects/{project_id}/entitlements/{entitlement_id}/products" \
  -H "Authorization: Bearer {SECRET_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "product_id": "prod1a2b3c4d5e"
  }'
```

#### 列出 Offerings
```bash
curl -s "https://api.revenuecat.com/v2/projects/{project_id}/offerings" \
  -H "Authorization: Bearer {SECRET_KEY}"
```

### RevenueCat API 權限

Secret API Key 需要以下權限：
- `project_configuration:apps:read_write` - 建立/管理 Apps
- `project_configuration:products:read_write` - 建立/管理產品
- `project_configuration:entitlements:read_write` - 管理權限
- `project_configuration:offerings:read_write` - 管理 Offerings

---

## Complete Automation Script

### Python Script: Create Multiple Subscriptions

```python
#!/usr/bin/env python3
"""
App Store Connect - Complete Subscription Setup Script
Creates subscription group, subscriptions, localizations, availability, and pricing.
"""

import jwt
import time
import os
import json
import requests

# Load credentials
# source ~/.app_store_credentials/.env before running
KEY_PATH = os.environ.get("APP_STORE_CONNECT_KEY_PATH")
KEY_ID = os.environ.get("APP_STORE_CONNECT_KEY_ID")
ISSUER_ID = os.environ.get("APP_STORE_CONNECT_ISSUER_ID")

BASE_URL = "https://api.appstoreconnect.apple.com/v1"

def generate_token():
    """Generate JWT token for App Store Connect API"""
    with open(KEY_PATH, "r") as f:
        private_key = f.read()

    return jwt.encode(
        {"iss": ISSUER_ID, "iat": int(time.time()), "exp": int(time.time()) + 1200, "aud": "appstoreconnect-v1"},
        private_key, algorithm="ES256", headers={"kid": KEY_ID}
    )

def get_headers():
    return {
        "Authorization": f"Bearer {generate_token()}",
        "Content-Type": "application/json"
    }

def create_subscription_group(app_id, reference_name):
    """Create a subscription group"""
    data = {
        "data": {
            "type": "subscriptionGroups",
            "attributes": {"referenceName": reference_name},
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}}
            }
        }
    }
    resp = requests.post(f"{BASE_URL}/subscriptionGroups", headers=get_headers(), json=data)
    return resp.json().get("data", {}).get("id") if resp.status_code in [200, 201] else None

def create_subscription(group_id, product_id, name, period):
    """Create a subscription in a group"""
    # period: ONE_MONTH, ONE_YEAR, ONE_WEEK, etc.
    data = {
        "data": {
            "type": "subscriptions",
            "attributes": {
                "name": name,
                "productId": product_id,
                "subscriptionPeriod": period,
                "reviewNote": f"Subscription for {name}"
            },
            "relationships": {
                "group": {"data": {"type": "subscriptionGroups", "id": group_id}}
            }
        }
    }
    resp = requests.post(f"{BASE_URL}/subscriptions", headers=get_headers(), json=data)
    return resp.json().get("data", {}).get("id") if resp.status_code in [200, 201] else None

def create_subscription_localization(sub_id, locale, name, description):
    """Create localization for a subscription"""
    data = {
        "data": {
            "type": "subscriptionLocalizations",
            "attributes": {
                "locale": locale,  # e.g., "zh-Hant", "en-US"
                "name": name,
                "description": description[:55]  # Max 55 chars
            },
            "relationships": {
                "subscription": {"data": {"type": "subscriptions", "id": sub_id}}
            }
        }
    }
    resp = requests.post(f"{BASE_URL}/subscriptionLocalizations", headers=get_headers(), json=data)
    return resp.status_code in [200, 201]

def create_subscription_availability(sub_id, territories):
    """Set subscription availability for territories"""
    territory_data = [{"type": "territories", "id": t} for t in territories]
    data = {
        "data": {
            "type": "subscriptionAvailabilities",
            "attributes": {"availableInNewTerritories": True},
            "relationships": {
                "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                "availableTerritories": {"data": territory_data}
            }
        }
    }
    resp = requests.post(f"{BASE_URL}/subscriptionAvailabilities", headers=get_headers(), json=data)
    return resp.status_code in [200, 201]

def find_price_point(sub_id, target_price, territory="TWN"):
    """Find price point ID for a specific price"""
    url = f"{BASE_URL}/subscriptions/{sub_id}/pricePoints"
    params = {"filter[territory]": territory, "limit": 200}

    all_points = []
    while url:
        resp = requests.get(url, headers=get_headers(), params=params)
        data = resp.json()
        all_points.extend(data.get("data", []))
        url = data.get("links", {}).get("next")
        params = {}

    for pt in all_points:
        customer_price = pt.get("attributes", {}).get("customerPrice", "")
        if customer_price:
            try:
                if abs(float(customer_price) - target_price) < 1:
                    return pt["id"]
            except:
                pass
    return None

def set_subscription_price(sub_id, price_point_id):
    """Set subscription price"""
    data = {
        "data": {
            "type": "subscriptionPrices",
            "relationships": {
                "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": price_point_id}}
            }
        }
    }
    resp = requests.post(f"{BASE_URL}/subscriptionPrices", headers=get_headers(), json=data)
    return resp.status_code in [200, 201]

def get_all_territories():
    """Get all available territories"""
    resp = requests.get(f"{BASE_URL}/territories?limit=200", headers=get_headers())
    return [t["id"] for t in resp.json().get("data", [])]

def main():
    APP_ID = "YOUR_APP_ID"  # Get from /v1/apps

    # Define subscriptions
    SUBSCRIPTIONS = [
        {"productId": "pro_monthly", "name": "Pro Monthly", "period": "ONE_MONTH", "price": 70},
        {"productId": "pro_yearly", "name": "Pro Yearly", "period": "ONE_YEAR", "price": 590},
        {"productId": "premium_monthly", "name": "Premium Monthly", "period": "ONE_MONTH", "price": 120},
        {"productId": "premium_yearly", "name": "Premium Yearly", "period": "ONE_YEAR", "price": 990},
    ]

    print("=== App Store Connect Subscription Setup ===\n")

    # 1. Create Subscription Group
    print("1. Creating Subscription Group...")
    group_id = create_subscription_group(APP_ID, "Premium Subscriptions")
    print(f"   Group ID: {group_id}")

    # 2. Get all territories
    print("\n2. Fetching territories...")
    territories = get_all_territories()
    print(f"   Found {len(territories)} territories")

    # 3. Create subscriptions
    print("\n3. Creating Subscriptions...")
    for sub in SUBSCRIPTIONS:
        print(f"\n   === {sub['productId']} ===")

        # Create subscription
        sub_id = create_subscription(group_id, sub["productId"], sub["name"], sub["period"])
        print(f"   Subscription ID: {sub_id}")

        if sub_id:
            # Create localization
            if create_subscription_localization(sub_id, "zh-Hant", sub["name"], f"訂閱 {sub['name']}"):
                print(f"   ✅ Localization created")

            # Set availability
            if create_subscription_availability(sub_id, territories):
                print(f"   ✅ Availability set")

            # Set price
            price_point_id = find_price_point(sub_id, sub["price"], "TWN")
            if price_point_id and set_subscription_price(sub_id, price_point_id):
                print(f"   ✅ Price set to NT${sub['price']}")

    print("\n=== Setup Complete ===")

if __name__ == "__main__":
    main()
```

### Usage

1. Set up credentials:
   ```bash
   source ~/.app_store_credentials/.env
   ```

2. Install dependencies:
   ```bash
   pip install pyjwt requests
   ```

3. Update `APP_ID` and `SUBSCRIPTIONS` in the script

4. Run:
   ```bash
   python3 asc_subscription_setup.py
   ```

### Important Notes

- **Product ID uniqueness**: Apple Product IDs are globally unique across ALL apps. If a Product ID is already used by another app, you must use a different ID (e.g., add app prefix: `myapp_pro_monthly`).

- **MISSING_METADATA state**: Subscriptions will show "MISSING_METADATA" until the app binary is first submitted. This is expected - they still work in Sandbox testing.

- **Locale codes**: Use `zh-Hant` for Traditional Chinese (NOT `zh-TW`), `zh-Hans` for Simplified Chinese, `en-US` for English.

---

## Screenshot Upload Guide

### CRITICAL: Image Requirements

> **GOTCHA**: Apple silently rejects screenshots with wrong DPI or color profile.
> The upload API returns success (`UPLOAD_COMPLETE`), but async processing fails
> with `IMAGE_INCORRECT_DIMENSIONS` — even when pixel dimensions are correct!

**Required image properties:**
- **DPI**: 72 (NOT 144 — iPhone screenshots default to 144 DPI)
- **Color Profile**: sRGB IEC61966-2.1 (NOT Display P3 — iPhone defaults to P3)
- **Format**: PNG (recommended) or JPEG
- **Pixel dimensions**: Must match display type exactly (see table below)

### Fix Images Before Upload

```bash
# Convert iPhone screenshot to App Store-compatible format
sips -z HEIGHT WIDTH \
  -s dpiWidth 72.0 -s dpiHeight 72.0 \
  -m "/System/Library/ColorSync/Profiles/sRGB Profile.icc" \
  INPUT.PNG --out OUTPUT.PNG
```

**Batch convert example (6.5"):**
```bash
for f in screenshots/originals/*.PNG; do
  sips -z 2688 1242 \
    -s dpiWidth 72.0 -s dpiHeight 72.0 \
    -m "/System/Library/ColorSync/Profiles/sRGB Profile.icc" \
    "$f" --out "screenshots/fixed_65/$(basename $f)"
done
```

### iPhone Screenshot Display Types

| Display Type | Pixel Size (Portrait) | Devices |
|---|---|---|
| `APP_IPHONE_67` | 1290 × 2796 | iPhone 14 Pro Max, 15 Pro Max, 16 Pro Max |
| `APP_IPHONE_65` | 1242 × 2688 | iPhone XS Max, 11 Pro Max |
| `APP_IPHONE_61` | 1179 × 2556 | iPhone 14, 15, 16 |
| `APP_IPHONE_55` | 1242 × 2208 | iPhone 6s Plus, 7 Plus, 8 Plus |

> **Minimum required**: 6.7" and 6.5" for new submissions. Apple auto-scales for smaller sizes.

### Upload via Python (Recommended)

The 3-step upload flow: **Reserve → Upload → Commit**

```python
import requests, hashlib, glob, os

def upload_screenshots(headers, loc_id, display_type, screenshot_dir):
    """Upload screenshots to App Store Connect.

    Args:
        headers: Auth headers with Bearer token
        loc_id: appStoreVersionLocalization ID
        display_type: e.g. "APP_IPHONE_65"
        screenshot_dir: directory containing fixed PNG files
    """
    BASE = "https://api.appstoreconnect.apple.com/v1"

    # 1. Find or create screenshot set
    r = requests.get(f"{BASE}/appStoreVersionLocalizations/{loc_id}/appScreenshotSets", headers=headers)
    target_set = next((s for s in r.json()["data"]
                       if s["attributes"]["screenshotDisplayType"] == display_type), None)

    if not target_set:
        r = requests.post(f"{BASE}/appScreenshotSets", headers=headers, json={
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": display_type},
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": loc_id}
                    }
                }
            }
        })
        target_set = r.json()["data"]

    set_id = target_set["id"]

    # 2. Delete existing screenshots in set
    r = requests.get(f"{BASE}/appScreenshotSets/{set_id}/appScreenshots", headers=headers)
    for sc in r.json()["data"]:
        requests.delete(f"{BASE}/appScreenshots/{sc['id']}", headers=headers)

    # 3. Upload each image
    for img_path in sorted(glob.glob(f"{screenshot_dir}/*.PNG")):
        fname = os.path.basename(img_path)
        with open(img_path, "rb") as f:
            file_data = f.read()
        md5 = hashlib.md5(file_data).hexdigest()

        # Reserve
        r = requests.post(f"{BASE}/appScreenshots", headers=headers, json={
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileName": fname, "fileSize": len(file_data)},
                "relationships": {
                    "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}
                }
            }
        })
        sc_data = r.json()["data"]
        sc_id = sc_data["id"]

        # Upload parts
        for op in sc_data["attributes"].get("uploadOperations", []):
            req_h = {h["name"]: h["value"] for h in op["requestHeaders"]}
            chunk = file_data[op["offset"]:op["offset"]+op["length"]]
            requests.request(op["method"], op["url"], headers=req_h, data=chunk)

        # Commit
        r = requests.patch(f"{BASE}/appScreenshots/{sc_id}", headers=headers, json={
            "data": {
                "type": "appScreenshots", "id": sc_id,
                "attributes": {"sourceFileChecksum": md5, "uploaded": True}
            }
        })
        state = r.json()["data"]["attributes"].get("assetDeliveryState", {}).get("state")
        print(f"  {fname}: {state}")
```

### Upload via Ruby (Spaceship)

```ruby
require 'spaceship'

# Auth
key_data = JSON.parse(File.read("api_key.json"))
token = Spaceship::ConnectAPI::Token.create(
  key_id: key_data["key_id"],
  issuer_id: key_data["issuer_id"],
  key: key_data["key"]
)
Spaceship::ConnectAPI.token = token

# Find app → version → localization → screenshot set
app = Spaceship::ConnectAPI::App.all(filter: { bundleId: "com.example.app" }).first
version = app.get_edit_app_store_version
loc = version.get_app_store_version_localizations(filter: { locale: "en-US" }).first
sets = loc.get_app_screenshot_sets(filter: { screenshotDisplayType: "APP_IPHONE_65" })
screenshot_set = sets.first || loc.create_app_screenshot_set(
  attributes: { screenshotDisplayType: "APP_IPHONE_65" }
)

# Clear and upload
screenshot_set.app_screenshots.each(&:delete!)
Dir.glob("screenshots/fixed_65/*.PNG").sort.each do |path|
  screenshot_set.upload_screenshot(path: path)
end
```

### Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `IMAGE_INCORRECT_DIMENSIONS` (FAILED after upload) | 144 DPI or Display P3 color profile | Convert to 72 DPI + sRGB before upload |
| `IMAGE_INCORRECT_DIMENSIONS` (immediate) | Wrong pixel dimensions | Check exact size for display type |
| Upload succeeds but state is FAILED | Async processing rejection | Check `assetDeliveryState.errors` for details |
| `ENTITY_ERROR` on screenshot set creation | Display type not valid for app | Check `TARGETED_DEVICE_FAMILY` in Xcode project |

### Common Pitfalls

1. **Spaceship "success" is misleading**: `upload_screenshot` returns OK even when Apple will reject the image during async processing. Always verify final state via API.

2. **iPhone screenshots default to 144 DPI + Display P3**: Even if you resize to exact pixel dimensions, Apple rejects if DPI ≠ 72 or color profile ≠ sRGB.

3. **Verify before moving on**: After upload, poll `appScreenshotSets/{id}/appScreenshots` and check `assetDeliveryState.state == "COMPLETE"` (not just `UPLOAD_COMPLETE`).

4. **Upload order matters**: Screenshots appear in upload order. Sort files before uploading.

---

## Version Localization Management

### State Restrictions (READY_FOR_SALE)

When the current version is `READY_FOR_SALE`, you can ONLY edit:
- ✅ **Promotional Text** — no review needed, instant update
- ❌ **Description, Keywords, Subtitle, Name** — requires creating a new version

| Field | Editable on READY_FOR_SALE? | API Endpoint |
|-------|----------------------------|--------------|
| Promotional Text | ✅ Yes | PATCH `appStoreVersionLocalizations/{id}` |
| Description | ❌ No (new version needed) | PATCH `appStoreVersionLocalizations/{id}` |
| Keywords | ❌ No (new version needed) | PATCH `appStoreVersionLocalizations/{id}` |
| Name | ❌ No | PATCH `appInfoLocalizations/{id}` |
| Subtitle | ❌ No | PATCH `appInfoLocalizations/{id}` |

### Creating a New Version for Metadata-Only Updates

```python
# Create new version (e.g., 1.0.1) — no new build required yet
r = requests.post(f"{BASE}/appStoreVersions", headers=HEADERS, json={
    "data": {
        "type": "appStoreVersions",
        "attributes": {"versionString": "1.0.1", "platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": APP_ID}}}
    }
})
new_version_id = r.json()["data"]["id"]
```

### Adding New Locales — Correct Workflow

> **GOTCHA**: Two different approaches depending on version state.

**Method 1: POST to `appStoreVersionLocalizations` (RECOMMENDED)**
Create version localization directly — works on PREPARE_FOR_SUBMISSION versions:
```python
r = requests.post(f"{BASE}/appStoreVersionLocalizations", headers=HEADERS, json={
    "data": {
        "type": "appStoreVersionLocalizations",
        "attributes": {
            "locale": "en-US",
            "description": "...",
            "keywords": "...",
            "promotionalText": "...",
        },
        "relationships": {
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}
        }
    }
})
```

**Method 2: POST to `appInfoLocalizations` (auto-creates version localization)**
This creates both appInfo (name/subtitle) and version (desc/keywords) localizations.
But **fails on PREPARE_FOR_SUBMISSION** with `409: A relationship cannot be created in current state`.

> **Rule**: Use Method 1 for version localizations, then separately update appInfoLocalizations for name/subtitle.

**If POST returns `409: Entity with locale already exists`** → Use PATCH instead:
```python
# Re-fetch to find the auto-created localization ID
r = requests.get(f"{BASE}/appStoreVersions/{vid}/appStoreVersionLocalizations", headers=HEADERS)
loc_id = next(loc["id"] for loc in r.json()["data"] if loc["attributes"]["locale"] == "en-US")

# PATCH instead of POST
r = requests.patch(f"{BASE}/appStoreVersionLocalizations/{loc_id}", headers=HEADERS, json={
    "data": {"type": "appStoreVersionLocalizations", "id": loc_id,
             "attributes": {"description": "...", "keywords": "...", "promotionalText": "..."}}
})
```

### Promotional Text Restrictions

> **CRITICAL**: Apple **rejects emoji characters** in Promotional Text.
> `🚕`, `🎯`, `🔥` etc. all return `409: Promotional Text can't contain the following character(s)`.
> Use plain text only.

### Government Data Compliance (iOS)

Same as Google Play — if the app references government information:
1. Add **disclaimer** at the top of the description
2. Include **direct .gov URL**
3. Avoid「官方」/ "official" unless government-affiliated

> **IMPORTANT**: If Google Play rejects for Misleading Claims, **proactively fix iOS too**.
> Apple has the same guidelines and will likely catch the same issue eventually.

---

## App Submission Metadata (Non-IAP)

### Content Rights Declaration

Set via PATCH on the app resource:

```python
resp = requests.patch(f"{BASE_URL}/apps/{app_id}", headers=headers, json={
    "data": {
        "type": "apps",
        "id": app_id,
        "attributes": {
            "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"
            # or "USES_THIRD_PARTY_CONTENT"
        }
    }
})
```

### Primary & Secondary Category

Set via PATCH on `appInfos`:

```python
resp = requests.patch(f"{BASE_URL}/appInfos/{app_info_id}", headers=headers, json={
    "data": {
        "type": "appInfos",
        "id": app_info_id,
        "relationships": {
            "primaryCategory": {
                "data": {"type": "appCategories", "id": "PRODUCTIVITY"}
            },
            "secondaryCategory": {
                "data": {"type": "appCategories", "id": "DEVELOPER_TOOLS"}
            }
        }
    }
})
```

**Common iOS Categories:** `PRODUCTIVITY`, `DEVELOPER_TOOLS`, `UTILITIES`, `BUSINESS`,
`EDUCATION`, `ENTERTAINMENT`, `SOCIAL_NETWORKING`, `FINANCE`, `HEALTH_AND_FITNESS`, `LIFESTYLE`

### Age Rating Declaration

**GOTCHA**: Must provide ALL fields in a single PATCH — omitting any field returns `409`.

```python
resp = requests.patch(f"{BASE_URL}/ageRatingDeclarations/{age_rating_id}", headers=headers, json={
    "data": {
        "type": "ageRatingDeclarations",
        "id": age_rating_id,  # Same as appInfo ID
        "attributes": {
            # Frequency: "NONE" / "INFREQUENT_OR_MILD" / "FREQUENT_OR_INTENSE"
            "alcoholTobaccoOrDrugUseOrReferences": "NONE",
            "contests": "NONE",
            "gamblingSimulated": "NONE",
            "horrorOrFearThemes": "NONE",
            "matureOrSuggestiveThemes": "NONE",
            "medicalOrTreatmentInformation": "NONE",
            "profanityOrCrudeHumor": "NONE",
            "sexualContentGraphicAndNudity": "NONE",
            "sexualContentOrNudity": "NONE",
            "violenceCartoonOrFantasy": "NONE",
            "violenceRealistic": "NONE",
            "violenceRealisticProlongedGraphicOrSadistic": "NONE",
            "gunsOrOtherWeapons": "NONE",
            # Boolean fields
            "unrestrictedWebAccess": False,
            "gambling": False,
            "lootBox": False,
            "messagingAndChat": False,
            "advertising": False,
            "healthOrWellnessTopics": False,
            "userGeneratedContent": False,
            "parentalControls": False,
            "ageAssurance": False,
        }
    }
})
```

**Note:** `unrestrictedWebAccess: True` pushes age rating to 17+.

> **Iterative Retry Pattern**: Apple occasionally adds/removes age rating fields. If PATCH returns `409 ENTITY_ERROR.ATTRIBUTE.UNKNOWN`, remove the offending field. If it returns `409 ENTITY_ERROR.ATTRIBUTE.REQUIRED`, add the missing field (default: `False` for boolean, `"NONE"` for string enum). Loop until `200`. The `gunsOrOtherWeapons` field uses string enum (`NONE`/`INFREQUENT_OR_MILD`/`FREQUENT_OR_INTENSE`), not boolean.

### App Pricing (Free)

```python
# Get FREE price point for USA
r = requests.get(f"{BASE_URL}/apps/{app_id}/appPricePoints?filter[territory]=USA&limit=1", headers=headers)
free_point_id = r.json()["data"][0]["id"]  # First point is always $0.00

# Create price schedule
resp = requests.post(f"{BASE_URL}/appPriceSchedules", headers=headers, json={
    "data": {
        "type": "appPriceSchedules",
        "relationships": {
            "app": {"data": {"type": "apps", "id": app_id}},
            "manualPrices": {"data": [{"type": "appPrices", "id": "${price0}"}]},
            "baseTerritory": {"data": {"type": "territories", "id": "USA"}}
        }
    },
    "included": [{
        "type": "appPrices",
        "id": "${price0}",
        "attributes": {"startDate": None},
        "relationships": {
            "appPricePoint": {"data": {"type": "appPricePoints", "id": free_point_id}}
        }
    }]
})
```

### App Name & Subtitle (per locale)

Set via PATCH on `appInfoLocalizations`:

```python
# First, find the appInfoLocalization ID:
# GET /v1/apps/{app_id}/appInfos → get appInfo ID
# GET /v1/appInfos/{info_id}/appInfoLocalizations → get localization IDs per locale

LOC_ID = "your-localization-id"

resp = requests.patch(f"{BASE_URL}/appInfoLocalizations/{LOC_ID}", headers=headers, json={
    "data": {
        "type": "appInfoLocalizations",
        "id": LOC_ID,
        "attributes": {
            "name": "My App Name",           # App Name (≤ 30 characters)
            "subtitle": "Short description"   # Subtitle (≤ 30 characters, STRICT)
        }
    }
})
```

**GOTCHA**: Subtitle has a **strict 30-character limit**. Exceeding it returns `409 ENTITY_ERROR.ATTRIBUTE.INVALID.TOO_LONG`. Count carefully — spaces and special characters (`&`, `-`) all count.

**Fields on `appInfoLocalizations`:**
- `name` — App display name on App Store (≤ 30 chars)
- `subtitle` — Shown below the name (≤ 30 chars)
- `privacyPolicyUrl` — Privacy policy link
- `privacyPolicyText` — Privacy policy text (optional)

### Privacy Policy URL (per locale)

Set via PATCH on `appInfoLocalizations` (NOT `appStoreVersionLocalizations`):

```python
resp = requests.patch(f"{BASE_URL}/appInfoLocalizations/{loc_id}", headers=headers, json={
    "data": {
        "type": "appInfoLocalizations",
        "id": loc_id,
        "attributes": {"privacyPolicyUrl": "https://example.com/privacy.html"}
    }
})
```

**GOTCHA**: `privacyPolicyUrl` is on `appInfoLocalizations`, NOT `appStoreVersionLocalizations`.
Support URL and marketing URL are on `appStoreVersionLocalizations`.

### Support URL & Marketing URL (per locale)

Set via PATCH on `appStoreVersionLocalizations`:

```python
resp = requests.patch(f"{BASE_URL}/appStoreVersionLocalizations/{loc_id}", headers=headers, json={
    "data": {
        "type": "appStoreVersionLocalizations",
        "id": loc_id,
        "attributes": {
            "supportUrl": "https://example.com/support.html",
            "marketingUrl": "https://example.com"
        }
    }
})
```

### App Review Detail

```python
resp = requests.patch(f"{BASE_URL}/appStoreReviewDetails/{review_id}", headers=headers, json={
    "data": {
        "type": "appStoreReviewDetails",
        "id": review_id,
        "attributes": {
            "demoAccountRequired": False,  # True if demo credentials needed
            "demoAccountName": "test@example.com",  # Only if required
            "demoAccountPassword": "password123",    # Only if required
            "notes": "Review instructions here"
        }
    }
})
```

### App Privacy (Data Collection Questionnaire)

**NO REST API available.** Must be filled in manually via App Store Connect web interface:
`https://appstoreconnect.apple.com/apps/{app_id}/appPrivacy`

This is the "nutrition label" data collection disclosure required for all apps.

---

### Territory Exclusion (Block Countries)

Use the v2 `appAvailabilities` API to exclude specific countries. Territory IDs are base64-encoded JSON.

**Step 1: Find territory availability ID**
```python
import base64, json

# Paginate through all territories
all_tas = []
url = f"https://api.appstoreconnect.apple.com/v2/appAvailabilities/{app_id}/territoryAvailabilities?limit=200"
while url:
    r = requests.get(url, headers=headers)
    data = r.json()
    all_tas.extend(data.get("data", []))
    url = data.get("links", {}).get("next")

# Find specific territory (e.g., CHN, KOR)
for ta in all_tas:
    try:
        decoded = json.loads(base64.b64decode(ta["id"] + "==").decode("utf-8"))
        if decoded.get("t") in ["CHN", "KOR"]:
            print(f"{decoded['t']}: id={ta['id']} available={ta['attributes']['available']}")
    except:
        pass
```

**Step 2: Set territory to unavailable**
```python
ta_id = "eyJz..."  # base64-encoded ID from Step 1
resp = requests.patch(
    f"https://api.appstoreconnect.apple.com/v1/territoryAvailabilities/{ta_id}",
    headers=headers,
    json={"data": {"type": "territoryAvailabilities", "id": ta_id, "attributes": {"available": False}}}
)
# 200 = success
```

**Common territory codes:** `CHN` (China), `KOR` (South Korea), `JPN` (Japan), `USA`, `TWN` (Taiwan)

---

### Review Submission / Resubmit After DEVELOPER_REJECTED

**GOTCHA**: `appStoreVersionSubmissions` (v1 legacy) does NOT allow CREATE on `DEVELOPER_REJECTED` versions. Use `reviewSubmissions` API instead.

```python
# Step 1: Create review submission
r = requests.post(f"{BASE_URL}/reviewSubmissions", headers=headers, json={
    "data": {
        "type": "reviewSubmissions",
        "attributes": {"platform": "IOS"},
        "relationships": {
            "app": {"data": {"type": "apps", "id": app_id}}
        }
    }
})
submission_id = r.json()["data"]["id"]

# Step 2: Add version as review item
r = requests.post(f"{BASE_URL}/reviewSubmissionItems", headers=headers, json={
    "data": {
        "type": "reviewSubmissionItems",
        "relationships": {
            "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}
        }
    }
})

# Step 3: Submit for review
r = requests.patch(f"{BASE_URL}/reviewSubmissions/{submission_id}", headers=headers, json={
    "data": {"type": "reviewSubmissions", "id": submission_id, "attributes": {"submitted": True}}
})
# 200 = success, version transitions to WAITING_FOR_REVIEW
```

**Cancel a submission** (works on `WAITING_FOR_REVIEW`):
```python
# Get submission ID
r = requests.get(f"{BASE_URL}/appStoreVersions/{version_id}/appStoreVersionSubmission", headers=headers)
sub_id = r.json()["data"]["id"]
# DELETE to cancel
requests.delete(f"{BASE_URL}/appStoreVersionSubmissions/{sub_id}", headers=headers)
# Version transitions to DEVELOPER_REJECTED
```

#### 🔴 CRITICAL: REJECTED Version API Limitations (2026-03 battle-tested)

When a version transitions from `REJECTED` → `PREPARE_FOR_SUBMISSION` (e.g., after selecting a new build), the following API operations are BLOCKED:

| Operation | Error | Workaround |
|-----------|-------|------------|
| Edit `whatsNew` via `appStoreVersionLocalizations` PATCH | 409 `STATE_ERROR` "cannot be edited at this time" | Use `fastlane deliver` (it has internal logic to handle this) |
| Cancel empty `READY_FOR_REVIEW` reviewSubmissions | 409 / 403 | Can't cancel - must reuse them (see below) |
| Delete the version | 409 "last version cannot be deleted" | N/A if only version |
| Create new version while REJECTED exists | 409 "cannot create in current state" | Update versionString on existing version |
| `appStoreVersionSubmissions` CREATE | 403 "only DELETE allowed" | Use `reviewSubmissions` API |

**Proven Resubmission Workflow After REJECTED:**

```python
# Step 1: Update version string if needed (e.g., 1.0.2 → 1.0.3)
requests.patch(f"{BASE_URL}/appStoreVersions/{version_id}", headers=headers, json={
    "data": {"type": "appStoreVersions", "id": version_id,
             "attributes": {"versionString": "1.0.3"}}
})

# Step 2: Select new build
requests.patch(f"{BASE_URL}/appStoreVersions/{version_id}", headers=headers, json={
    "data": {"type": "appStoreVersions", "id": version_id,
             "relationships": {"build": {"data": {"type": "builds", "id": new_build_id}}}}
})
# Version transitions to PREPARE_FOR_SUBMISSION

# Step 3: Update review notes (this WORKS even on REJECTED versions)
r = requests.get(f"{BASE_URL}/appStoreVersions/{version_id}/appStoreReviewDetail", headers=headers)
review_detail_id = r.json()["data"]["id"]
requests.patch(f"{BASE_URL}/appStoreReviewDetails/{review_detail_id}", headers=headers, json={
    "data": {"type": "appStoreReviewDetails", "id": review_detail_id,
             "attributes": {"notes": "Your review notes here..."}}
})

# Step 4: Upload metadata via fastlane deliver (handles whatsNew correctly)
# fastlane submit  (or fastlane deliver --skip_binary_upload --submit_for_review)

# Step 5: If fastlane fails with "review submission already in progress",
# reuse an existing READY_FOR_REVIEW submission:
r = requests.get(f"{BASE_URL}/apps/{app_id}/reviewSubmissions?filter[state]=READY_FOR_REVIEW&limit=1", headers=headers)
existing_sub = r.json()["data"][0]
sid = existing_sub["id"]

# Add version as item to existing submission
requests.post(f"{BASE_URL}/reviewSubmissionItems", headers=headers, json={
    "data": {"type": "reviewSubmissionItems",
             "relationships": {
                 "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": sid}},
                 "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}
             }}
})

# Submit
requests.patch(f"{BASE_URL}/reviewSubmissions/{sid}", headers=headers, json={
    "data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}
})
# 200 = WAITING_FOR_REVIEW 🎉
```

**Key insight**: Creating multiple `reviewSubmissions` via API leaves zombie submissions in `READY_FOR_REVIEW` that CANNOT be canceled. Instead of creating new ones, always check for existing `READY_FOR_REVIEW` submissions first and reuse them.

---

### Localization Management (Create/Delete locales)

**Create new locale on version** (only works when version is editable, NOT `WAITING_FOR_REVIEW`):
```python
r = requests.post(f"{BASE_URL}/appStoreVersionLocalizations", headers=headers, json={
    "data": {
        "type": "appStoreVersionLocalizations",
        "attributes": {"locale": "ja", "description": "...", "keywords": "..."},
        "relationships": {
            "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}
        }
    }
})
```

**Create new locale on app info** (name/subtitle):
```python
r = requests.post(f"{BASE_URL}/appInfoLocalizations", headers=headers, json={
    "data": {
        "type": "appInfoLocalizations",
        "attributes": {"locale": "ja", "name": "App Name", "subtitle": "Subtitle"},
        "relationships": {
            "appInfo": {"data": {"type": "appInfos", "id": info_id}}
        }
    }
})
```

**Delete a locale:**
```python
requests.delete(f"{BASE_URL}/appStoreVersionLocalizations/{loc_id}", headers=headers)  # version loc
requests.delete(f"{BASE_URL}/appInfoLocalizations/{loc_id}", headers=headers)  # app info loc
```

**GOTCHA**: `whatsNew` (release notes) cannot be edited on `DEVELOPER_REJECTED` versions. Omit it from PATCH requests.

---

## References

- [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi)
- [Creating API Keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)
- [In-App Purchase Management](https://developer.apple.com/documentation/appstoreconnectapi/app_store/in-app_purchases)
- [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi)
- [RevenueCat REST API v2](https://www.revenuecat.com/docs/api-v2)
- [RevenueCat API Reference](https://www.revenuecat.com/reference/revenuecat-rest-api)
