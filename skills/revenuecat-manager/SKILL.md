---
name: revenuecat-manager
description: RevenueCat IAP configuration manager. Use this skill when the user needs to manage RevenueCat products, offerings, packages, entitlements, or check subscription status via the RevenueCat REST API v2. Triggers on keywords like "RevenueCat", "IAP configuration", "subscription products", "offerings", "packages", "entitlements".
allowed-tools: Bash, Read, Write, Grep, Glob
---

# RevenueCat Manager Skill

This skill enables you to manage RevenueCat In-App Purchase (IAP) configuration through the REST API v2.

> [!CAUTION]
> ## Mandatory Completion Checklist
> When setting up RevenueCat for a new app, you MUST complete ALL steps:
> **NEVER skip a step or leave placeholder keys in `.env`.**
>
> - [ ] Create iOS + Android apps in the project
> - [ ] Create entitlement (match code's `entitlementId`, typically `pro`)
> - [ ] Create offering + set as current (via Dashboard if API can't)
> - [ ] Create packages (`$rc_monthly`, `$rc_annual`)
> - [ ] Create products (iOS: `product_id`, Android: `subscriptionId:basePlanId`)
> - [ ] Attach products → packages
> - [ ] Attach products → entitlement
> - [ ] **Get public SDK keys from Dashboard** (`appl_*`, `goog_*`) — NOT available via API
> - [ ] **Update project `.env`** with real keys (replace any `placeholder` values)
> - [ ] Save config to `~/.revenuecat/.env` for future reference
>
> ### Cross-Skill Pipeline (Full IAP Setup)
> RevenueCat alone is NOT enough. You also need store-side products:
> 1. **apple-appstore-manager** → ASC subscription group + subscriptions + pricing
> 2. **google-play-manager** → Google Play subscriptions + basePlans + activate
> 3. **This skill** (revenuecat-manager) → RC configuration + SDK keys

## Authentication

### API Key Location
Search for the RevenueCat Secret API Key in these locations (in order):
1. **Project `.env` file** (e.g., `deploy/.env`, `.env`, `.env.local`)
2. **Global credentials**: `~/.revenuecat/.env`
3. **Environment variable**: `REVENUECAT_API_KEY` or `REVENUECAT_V2_API_KEY`

```bash
# Check project-level first
grep -r 'REVENUECAT' .env deploy/.env .env.local 2>/dev/null
# Then global
cat ~/.revenuecat/.env 2>/dev/null
```

### Store Credentials Location

Apple/Google credentials are stored centrally and should be **copied to each project** that needs them:

| Credential | Central Location | Per-Project Destination |
|---|---|---|
| **iOS Subscription P8 Key** | `~/.app_store_credentials/SubscriptionKey_*.p8` | `<project>/ios/keys/` or `<project>/credentials/` |
| **iOS ASC Auth P8 Key** | `~/.app_store_credentials/AuthKey_*.p8` | `<project>/ios/keys/` or `<project>/credentials/` |
| **Google Play Service Account** | `<any_project>/android/fastlane/play_store_key.json` | `<project>/android/fastlane/play_store_key.json` |

```bash
# Discover existing credentials
ls ~/.app_store_credentials/*.p8 2>/dev/null
cat ~/.app_store_credentials/.env 2>/dev/null  # Contains Key ID, Issuer ID, Team ID
find ~/Documents -name 'play_store_key.json' -maxdepth 5 2>/dev/null
```

> **IMPORTANT**: These files contain private keys. Always ensure they are in `.gitignore`. Never commit them to git.

If no key exists, ask the user to provide their RevenueCat Secret API Key from:
Dashboard > Project Settings > API Keys

### API Key Versions (v1 vs v2)

| Version | Prefix | Capabilities | Notes |
|---------|--------|-------------|-------|
| **v1 (Legacy)** | `sk_` | Webhook validation, basic REST | Older projects may only have this |
| **v2** | `sk_` (newer) | Full REST API v2: create entitlements, products, offerings | Required for programmatic management |

> Both use `sk_` prefix — they look similar. You can identify v2 keys by trying a v2 endpoint (e.g., `GET /v2/projects`). If it returns 401, it's a v1 key.
> Store both if available: `REVENUECAT_API_KEY` (v1) and `REVENUECAT_V2_API_KEY` (v2).

### Request Format

**IMPORTANT:** `curl` with single-quoted arguments often fails in Claude Code's bash tool due to shell quoting issues. Always use **`python3` with `requests`** instead:

```python
import requests
headers = {"Authorization": "Bearer sk_xxxxxxxxxxxxx", "Content-Type": "application/json"}
r = requests.get("https://api.revenuecat.com/v2/endpoint", headers=headers)
print(r.json())
```

If you must use curl, use double quotes with variable substitution:
```bash
API_KEY="sk_xxxxxxxxxxxxx"
curl -s -X GET "https://api.revenuecat.com/v2/endpoint" -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json"
```

## Common Operations

### 1. List All Projects
```bash
curl -s 'https://api.revenuecat.com/v2/projects' \
  -H 'Authorization: Bearer $API_KEY'
```

### 2. List Apps in Project
```bash
curl -s 'https://api.revenuecat.com/v2/projects/{project_id}/apps' \
  -H 'Authorization: Bearer $API_KEY'
```

### 3. List All Products
```bash
curl -s 'https://api.revenuecat.com/v2/projects/{project_id}/products' \
  -H 'Authorization: Bearer $API_KEY'
```

### 4. Create iOS App (App Store)
```bash
curl -s -X POST 'https://api.revenuecat.com/v2/projects/{project_id}/apps' \
  -H 'Authorization: Bearer $API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "My App (App Store)",
    "type": "app_store",
    "app_store": {
      "bundle_id": "com.example.myapp"
    }
  }'
```

> [!WARNING]
> **API App Creation with P8 Key Often Returns 500**
> Creating an iOS App Store app via API with embedded `subscription_private_key` (P8 key contents) frequently returns HTTP 500 Server Error.
> **Workaround**: Create the app via API WITHOUT credentials (bundle_id only), then upload P8 keys via Playwright UI (see §5b below).
> Alternatively, create the app entirely through the RC Dashboard UI.

**For full StoreKit 2 support** (usually fails via API — use Dashboard UI instead):
```json
{
  "name": "My App (App Store)",
  "type": "app_store",
  "app_store": {
    "bundle_id": "com.example.myapp",
    "subscription_key_id": "KEY_ID_FROM_ASC",
    "subscription_key_issuer": "ISSUER_ID_FROM_ASC",
    "subscription_private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
  }
}
```

### 5. Create Android App (Play Store)
```bash
curl -s -X POST 'https://api.revenuecat.com/v2/projects/{project_id}/apps' \
  -H 'Authorization: Bearer $API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "My App (Play Store)",
    "type": "play_store",
    "play_store": {
      "package_name": "com.example.myapp"
    }
  }'
```

### 5b. Uploading Keys via Playwright (UI Automation) — RECOMMENDED for iOS

Creating iOS App Store apps with P8 credential upload is **best done via Playwright UI**, since the API often returns 500 when embedding P8 keys.

**Dashboard Navigation Path** (verified 2026-03):
1. Navigate to: `https://app.revenuecat.com/projects/{project_id}/apps`
2. Click **"Apps & providers"** in left sidebar
3. Click **"Add app config"**
4. Select **"App Store"** (iOS)
5. Fill in App name + Bundle ID
6. Upload **In-app purchase key** (P8 file) → Key ID auto-fills, manually fill Issuer ID
7. Upload **App Store Connect API key** (AuthKey P8 file) → fill Key ID + Issuer ID
8. Click **Save changes**

> [!IMPORTANT]
> **Do NOT use `/apps/new` path** — it returns 404. Always navigate through "Apps & providers" → "Add app config".
> **Issuer ID** is the same for both IAP key and ASC API key (Apple shares one issuer per team).

**Playwright File Upload Pattern** (using `browser_run_code` + `browser_file_upload`):

```javascript
// Step 1: Trigger file chooser dialog
const [fileChooser] = await Promise.all([
  page.waitForEvent('filechooser'),
  page.locator('text=Drop a file here, or click to select').first().click()
]);
// Step 2: If using Playwright MCP, call browser_file_upload tool instead of setFiles
// The file chooser dialog remains open until a file is selected
await fileChooser.setFiles('/path/to/SubscriptionKey_XXXXX.p8');
```

> [!TIP]
> After uploading the first P8 (IAP), click "Add new key" for the ASC API section, then repeat the upload pattern for the AuthKey P8.

### 6. Create a Product
```bash
curl -s -X POST 'https://api.revenuecat.com/v2/projects/{project_id}/products' \
  -H 'Authorization: Bearer $API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "app_id": "app_xxxxx",
    "store_identifier": "product_id",
    "display_name": "Product Name",
    "type": "subscription"
  }'
```

**Important - Store Identifier Format:**

| Platform | Format | Example |
|----------|--------|---------|
| **iOS (App Store)** | Just the product ID | `pro_monthly` |
| **Android (Play Store)** | `subscriptionId:basePlanId` | `pro_monthly:monthly` |

### 7. Create Entitlement
```bash
curl -s -X POST 'https://api.revenuecat.com/v2/projects/{project_id}/entitlements' \
  -H 'Authorization: Bearer $API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "lookup_key": "pro",
    "display_name": "Pro Access"
  }'
```

### 8. Create Offering
```bash
curl -s -X POST 'https://api.revenuecat.com/v2/projects/{project_id}/offerings' \
  -H 'Authorization: Bearer $API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "lookup_key": "default",
    "display_name": "Default Offering"
  }'
```

### 9. Create Package in Offering
```bash
curl -s -X POST 'https://api.revenuecat.com/v2/projects/{project_id}/offerings/{offering_id}/packages' \
  -H 'Authorization: Bearer $API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "lookup_key": "pro_monthly",
    "display_name": "Pro Monthly"
  }'
```

**Standard Package Lookup Keys:**
- `$rc_monthly` - Monthly subscription
- `$rc_annual` - Annual subscription
- `$rc_lifetime` - Lifetime purchase
- Custom keys like `pro_monthly`, `premium_yearly` are also valid

### 10. List Offerings
```bash
curl -s 'https://api.revenuecat.com/v2/projects/{project_id}/offerings' \
  -H 'Authorization: Bearer $API_KEY'
```

### 11. List Packages in Offering
```bash
curl -s 'https://api.revenuecat.com/v2/projects/{project_id}/offerings/{offering_id}/packages' \
  -H 'Authorization: Bearer $API_KEY'
```

### 12. List Products in Package
```bash
curl -s 'https://api.revenuecat.com/v2/projects/{project_id}/packages/{package_id}/products' \
  -H 'Authorization: Bearer $API_KEY'
```

### 13. Attach Products to Package
```bash
curl -s -X POST 'https://api.revenuecat.com/v2/projects/{project_id}/packages/{package_id}/actions/attach_products' \
  -H 'Authorization: Bearer $API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "products": [
      {"product_id": "prod_xxxxx", "eligibility_criteria": "all"}
    ]
  }'
```

**Eligibility Criteria Options:**
- `all` - Available to all users
- `new_customer` - Only new customers
- `expired_subscriber` - Only users with expired subscriptions

### 14. Detach Products from Package
```bash
curl -s -X POST 'https://api.revenuecat.com/v2/projects/{project_id}/packages/{package_id}/actions/detach_products' \
  -H 'Authorization: Bearer $API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "product_ids": ["prod_xxxxx"]
  }'
```

### 14b. Delete a Package
```bash
# NOTE: Use /packages/{package_id} directly, NOT /offerings/{offering_id}/packages/{package_id}
curl -s -X DELETE 'https://api.revenuecat.com/v2/projects/{project_id}/packages/{package_id}' \
  -H 'Authorization: Bearer $API_KEY'
```

### 14c. Delete an Offering (and all its packages)
```bash
curl -s -X DELETE 'https://api.revenuecat.com/v2/projects/{project_id}/offerings/{offering_id}' \
  -H 'Authorization: Bearer $API_KEY'
```

### 14d. Delete a Product
```bash
curl -s -X DELETE 'https://api.revenuecat.com/v2/projects/{project_id}/products/{product_id}' \
  -H 'Authorization: Bearer $API_KEY'
# Must detach from all packages and entitlements first, otherwise returns 422
```

### 14e. Delete an Entitlement
```bash
curl -s -X DELETE 'https://api.revenuecat.com/v2/projects/{project_id}/entitlements/{entitlement_id}' \
  -H 'Authorization: Bearer $API_KEY'
# Must detach all products first, otherwise returns 422
```

### 14f. Detach Products from Entitlement
```bash
curl -s -X POST 'https://api.revenuecat.com/v2/projects/{project_id}/entitlements/{entitlement_id}/actions/detach_products' \
  -H 'Authorization: Bearer $API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "product_ids": ["prod_xxxxx"]
  }'
```

### 15. List Entitlements
```bash
curl -s 'https://api.revenuecat.com/v2/projects/{project_id}/entitlements' \
  -H 'Authorization: Bearer $API_KEY'
```

### 16. Attach Products to Entitlement
```bash
curl -s -X POST 'https://api.revenuecat.com/v2/projects/{project_id}/entitlements/{entitlement_id}/actions/attach_products' \
  -H 'Authorization: Bearer $API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "product_ids": ["prod_xxxxx"]
  }'
```

### 17. Get Customer Info
```bash
curl -s 'https://api.revenuecat.com/v2/projects/{project_id}/customers/{customer_id}' \
  -H 'Authorization: Bearer $API_KEY'
```

### 18. Get Customer Subscriptions
```bash
curl -s 'https://api.revenuecat.com/v2/projects/{project_id}/customers/{customer_id}/subscriptions' \
  -H 'Authorization: Bearer $API_KEY'
```

## Workflow: Diagnose "Product Not Available" Error

When a user reports "Product not available" in their app:

1. **Get the API key** from project `.env` or `~/.revenuecat/.env`
2. **List projects** to get project_id
3. **List apps** to identify App Store and Play Store apps
4. **List products** to see all created products
5. **List offerings** to get offering_id
6. **List packages** in the default offering
7. **For each package**, list attached products
8. **Verify** each package has products for:
   - App Store (app_id starts with `app19f...` or similar)
   - Play Store (app_id starts with `appdac...` or similar)
9. **If missing**, create products and attach them to packages

## Workflow: Diagnose NO_ELIGIBLE_OFFER Error

When RevenueCat logs show `NO_ELIGIBLE_OFFER` for a Google Play subscription:

1. **Check RevenueCat products** — Verify Android `store_identifier` uses `subscriptionId:basePlanId` format (e.g., `yourapp_pro:monthly`)
2. **Check Google Play subscription** — Use Google Play API to verify base plans are ACTIVE
3. **Check regional availability** — The most common cause: the test user's country is NOT in the base plan's `regionalConfigs`. Even with `otherRegionsConfig.newSubscriberAvailability: true`, BillingClient may fail to resolve offers for newly created subscriptions
4. **Fix**: Add the target region explicitly to the base plan's `regionalConfigs` via Google Play API (PATCH the subscription)
5. **Clear Play Store data** on the test device after making changes
6. **Verify License Testing** — Ensure the Google account is in Settings → License Testing (different from internal test track testers)

## Workflow: Complete IAP Setup

1. **Create Entitlement** (e.g., "pro")
2. **Create Offering** (e.g., "default")
3. **Create Packages** in offering:
   - Monthly (`$rc_monthly`)
   - Yearly (`$rc_annual`)
4. **Create Products** for each store:
   - App Store products (one per package)
   - Play Store products (one per package, with `subscriptionId:basePlanId` format)
5. **Attach Products** to Packages
6. **Attach Products** to Entitlement
7. **Create Webhook** for server-side event processing

### 18. Create Webhook
```python
requests.post(f"{BASE}/projects/{PROJECT}/integrations/webhooks", headers=headers, json={
    "name": "My Backend Webhook",
    "url": "https://api.example.com/webhooks/revenuecat",
    "authorization_header": "Bearer YOUR_WEBHOOK_SECRET",
    "environment": "production",
    "event_types": [
        "initial_purchase", "renewal", "non_renewing_purchase",
        "cancellation", "expiration", "product_change",
        "billing_issue", "uncancellation", "transfer", "subscription_extended"
    ]
})
```

**Valid event_types** (do NOT use `test` — it's not valid):
`initial_purchase`, `renewal`, `product_change`, `cancellation`, `billing_issue`,
`non_renewing_purchase`, `uncancellation`, `transfer`, `expiration`,
`subscription_extended`, `subscription_paused`, `invoice_issuance`,
`temporary_entitlement_grant`, `refund_reversed`, `virtual_currency_transaction`

## Error Handling

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `resource_missing` | Invalid ID | Verify project/package/product IDs |
| `unprocessable_entity_error` | Incompatible product already attached | Check existing products first |
| `Play Store format error` | Wrong store_identifier | Use `subscriptionId:basePlanId` format |
| Rate limit (429) | Too many requests | Wait and retry with backoff |

### Rate Limits
- ~60 requests per minute (variable)
- Monitor `RevenueCat-Rate-Limit-Current-Usage` header
- Implement exponential backoff for 429 errors

## ID Patterns

| Type | Prefix | Example |
|------|--------|---------|
| Project | `proj` | `<YOUR_PROJECT_ID>` |
| App | `app` | `<YOUR_APP_ID>` |
| Product | `prod` | `prod93fe2a6ca2` |
| Offering | `ofrng` | `ofrng504b183bbd` |
| Package | `pkg` | `pkge57eae13bc9` |
| Entitlement | `entl` | `entla1b2c3d4e5` |

## Security Notes

- Secret API keys (`sk_*`) must NEVER be committed to git
- Store keys in gitignored files: project `.env`, `deploy/.env`, or `~/.revenuecat/.env`
- Public API keys (`appl_*`, `goog_*`) are safe for client-side use
- Rotate secret keys regularly

## Complete Automation Workflow

### Python Script: Full IAP Setup

```python
#!/usr/bin/env python3
"""
RevenueCat Complete IAP Setup Script
Creates apps, products, offerings, packages, entitlements and links them together.
"""

import requests
import json

# Configuration
RC_KEY = "sk_xxxxxxxxxxxxx"  # Your Secret API Key
PROJECT_ID = "xxxxxxxx"       # Project ID (without 'proj' prefix)
BASE_URL = "https://api.revenuecat.com/v2"

headers = {
    "Authorization": f"Bearer {RC_KEY}",
    "Content-Type": "application/json"
}

# Define your subscription products
SUBSCRIPTIONS = [
    {"id": "pro_monthly", "name": "Pro Monthly", "entitlement": "pro"},
    {"id": "pro_yearly", "name": "Pro Yearly", "entitlement": "pro"},
    {"id": "premium_monthly", "name": "Premium Monthly", "entitlement": "premium"},
    {"id": "premium_yearly", "name": "Premium Yearly", "entitlement": "premium"},
]

def create_app(name, app_type, identifier):
    """Create an app (iOS or Android)"""
    if app_type == "app_store":
        data = {"name": name, "type": "app_store", "app_store": {"bundle_id": identifier}}
    else:
        data = {"name": name, "type": "play_store", "play_store": {"package_name": identifier}}

    resp = requests.post(f"{BASE_URL}/projects/{PROJECT_ID}/apps", headers=headers, json=data)
    return resp.json().get("id") if resp.status_code in [200, 201] else None

def create_entitlement(lookup_key, display_name):
    """Create an entitlement"""
    data = {"lookup_key": lookup_key, "display_name": display_name}
    resp = requests.post(f"{BASE_URL}/projects/{PROJECT_ID}/entitlements", headers=headers, json=data)
    return resp.json().get("id") if resp.status_code in [200, 201] else None

def create_offering(lookup_key, display_name):
    """Create an offering"""
    data = {"lookup_key": lookup_key, "display_name": display_name}
    resp = requests.post(f"{BASE_URL}/projects/{PROJECT_ID}/offerings", headers=headers, json=data)
    return resp.json().get("id") if resp.status_code in [200, 201] else None

def create_package(offering_id, lookup_key, display_name):
    """Create a package in an offering"""
    data = {"lookup_key": lookup_key, "display_name": display_name}
    resp = requests.post(f"{BASE_URL}/projects/{PROJECT_ID}/offerings/{offering_id}/packages", headers=headers, json=data)
    return resp.json().get("id") if resp.status_code in [200, 201] else None

def create_product(app_id, store_identifier, display_name, is_android=False):
    """Create a product"""
    data = {
        "app_id": app_id,
        "store_identifier": store_identifier,
        "display_name": display_name,
        "type": "subscription"
    }
    resp = requests.post(f"{BASE_URL}/projects/{PROJECT_ID}/products", headers=headers, json=data)
    return resp.json().get("id") if resp.status_code in [200, 201] else None

def attach_product_to_package(package_id, product_id):
    """Attach a product to a package"""
    data = {"products": [{"product_id": product_id, "eligibility_criteria": "all"}]}
    resp = requests.post(f"{BASE_URL}/projects/{PROJECT_ID}/packages/{package_id}/actions/attach_products", headers=headers, json=data)
    return resp.status_code in [200, 201]

def attach_product_to_entitlement(entitlement_id, product_id):
    """Attach a product to an entitlement"""
    data = {"product_ids": [product_id]}
    resp = requests.post(f"{BASE_URL}/projects/{PROJECT_ID}/entitlements/{entitlement_id}/actions/attach_products", headers=headers, json=data)
    return resp.status_code in [200, 201]

def main():
    print("=== RevenueCat IAP Setup ===\n")

    # 1. Create Apps
    print("1. Creating Apps...")
    ios_app_id = create_app("My App (App Store)", "app_store", "com.example.myapp")
    android_app_id = create_app("My App (Play Store)", "play_store", "com.example.myapp")
    print(f"   iOS: {ios_app_id}, Android: {android_app_id}")

    # 2. Create Entitlements
    print("\n2. Creating Entitlements...")
    entitlements = {}
    for e in ["pro", "premium"]:
        entitlements[e] = create_entitlement(e, f"{e.title()} Access")
        print(f"   {e}: {entitlements[e]}")

    # 3. Create Offering
    print("\n3. Creating Offering...")
    offering_id = create_offering("default", "Default Offering")
    print(f"   default: {offering_id}")

    # 4. Create Packages and Products
    print("\n4. Creating Packages and Products...")
    for sub in SUBSCRIPTIONS:
        # Create package
        pkg_id = create_package(offering_id, sub["id"], sub["name"])
        print(f"   Package {sub['id']}: {pkg_id}")

        # Create iOS product (just product ID)
        ios_prod_id = create_product(ios_app_id, sub["id"], sub["name"])
        print(f"     iOS Product: {ios_prod_id}")

        # Create Android product (subscriptionId:basePlanId format)
        base_plan = "monthly" if "monthly" in sub["id"] else "yearly"
        android_prod_id = create_product(android_app_id, f"{sub['id']}:{base_plan}", sub["name"])
        print(f"     Android Product: {android_prod_id}")

        # Attach to package
        if ios_prod_id:
            attach_product_to_package(pkg_id, ios_prod_id)
            attach_product_to_entitlement(entitlements[sub["entitlement"]], ios_prod_id)
        if android_prod_id:
            attach_product_to_package(pkg_id, android_prod_id)
            attach_product_to_entitlement(entitlements[sub["entitlement"]], android_prod_id)

    print("\n=== Setup Complete ===")

if __name__ == "__main__":
    main()
```

### Usage

1. Replace `RC_KEY` with your Secret API Key from RevenueCat Dashboard
2. Replace `PROJECT_ID` with your project ID
3. Customize `SUBSCRIPTIONS` list with your products
4. Run: `python3 revenuecat_setup.py`

## Response Format

All API responses follow this structure:

```json
{
  "object": "item_type",
  "id": "item_id",
  "items": [...],  // For list operations
  "next_page": "cursor"  // For pagination
}
```

### Pagination

When listing items, use `next_page` cursor:
```bash
curl -s 'https://api.revenuecat.com/v2/projects/{project_id}/products?starting_after={cursor}' \
  -H 'Authorization: Bearer $API_KEY'
```

## Dashboard-Only Operations (No API)

These operations **cannot** be reliably done via REST API and require the RevenueCat Dashboard UI:

| Operation | Dashboard Location | Notes |
|-----------|-------------------|-------|
| **Create iOS App Store app w/ credentials** | Apps & providers → Add app config → App Store | API returns 500 with P8 keys |
| Upload iOS P8 subscription key + Key ID + Issuer ID | Apps & providers → App Store App → In-app purchase key | |
| Upload iOS ASC AuthKey + Key ID + Issuer ID | Apps & providers → App Store App → App Store Connect API | |
| Upload Google Play service account JSON | Apps & providers → Play Store App → Service credentials | |
| Google developer notifications (Pub/Sub topic) | Apps & providers → Play Store App → Google developer notifications |
| View/copy public SDK key (`goog_*`, `appl_*`) | API keys page |

### Workflow: Store Credentials Setup via Playwright

When configuring store credentials via the Dashboard using Playwright MCP:

#### iOS App Setup
1. Navigate to `https://app.revenuecat.com/projects/{project_id}/apps/{ios_app_id}`
2. Fill **App Bundle ID** (e.g., `com.example.myapp`)
3. **In-app purchase key section**: Upload `SubscriptionKey_*.p8`, fill Key ID and Issuer ID
4. **App Store Connect API section**: Upload `AuthKey_*.p8`, fill Key ID and Issuer ID
5. Click **Save changes**

#### Android App Setup
1. Navigate to `https://app.revenuecat.com/projects/{project_id}/apps/{android_app_id}`
2. **Service account credentials**: Upload `play_store_key.json`
3. Click **Save changes**

#### Playwright File Upload Restriction
> **CRITICAL**: Playwright MCP `browser_file_upload` only allows files **inside the project workspace root**. If credential files are stored outside (e.g., `~/.app_store_credentials/`), you must:
> 1. **Copy** the file into the project directory temporarily
> 2. **Upload** via Playwright
> 3. **Delete** the copy from the project directory (security hygiene)
>
> Use `browser_run_code` with `page.waitForEvent('filechooser')` pattern for reliable file uploads:
> ```javascript
> const [fileChooser] = await Promise.all([
>   page.waitForEvent('filechooser'),
>   page.locator('text=Drop a file here, or click to select').first().click()
> ]);
> await fileChooser.setFiles('/path/inside/project/key.p8');
> ```

#### Verify Save Success
Check network requests for `PATCH .../apps/{app_id} => [200]` to confirm save succeeded.
The warning banner "missing its In-App Purchase Key" may persist in the DOM even after a successful save — verify via network response, not UI.

### Google RTDN Setup (Manual + CLI)
1. **Enable Pub/Sub API** on the SA's **home GCP project** (NOT your main project):
   ```bash
   gcloud services enable pubsub.googleapis.com --project=<SA_HOME_PROJECT>
   ```
   **GOTCHA**: RevenueCat checks Pub/Sub API on the GCP project that OWNS the service account, not your app's project.
2. **Grant SA Pub/Sub Editor** role in its home project (via IAM console or gcloud)
3. **RevenueCat Dashboard**: Click "Connect to Google" — RevenueCat auto-creates the topic
4. **Grant Google Play publish permission** on the new topic:
   ```bash
   gcloud auth activate-service-account --key-file=<SA_KEY_FILE>
   gcloud pubsub topics add-iam-policy-binding <TOPIC_NAME> \
     --project=<SA_HOME_PROJECT> \
     --member="serviceAccount:google-play-developer-notifications@system.gserviceaccount.com" \
     --role="roles/pubsub.publisher"
   ```
5. **Google Play Console**: Monetize → Monetization Setup → paste topic ID (e.g. `projects/<project>/topics/Play-Store-Notifications`), select "Subscriptions, voided purchases, and all one-time products"
6. Send test notification from Play Console, verify "Last received" shows in RevenueCat
7. Enable "Track new purchases from server-to-server notifications" checkbox in RevenueCat

## References

- [RevenueCat API v2 Docs](https://www.revenuecat.com/docs/api-v2)
- [API Reference](https://www.revenuecat.com/reference/revenuecat-rest-api)
- [Dashboard](https://app.revenuecat.com)

## Related skills

- **`firebase-flutter-setup`** → **`firebase-auth-manager`** → **`admob-ux-best-practices`** → **`revenuecat-manager`** — use in sequence for monetized apps. Firebase sets up backend, auth implements sign-in, admob handles ads, revenuecat handles subscriptions.
- **`flutter-verify`** — after configuring RevenueCat, verify subscription purchase flows work end-to-end on real devices (purchase, restoration, entitlement gating).
