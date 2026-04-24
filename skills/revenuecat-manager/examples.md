# RevenueCat API - Practical Examples

These are ready-to-use curl commands. Replace `$API_KEY` with your secret key.

## Quick Diagnostic Commands

### Check Full Configuration Status
```bash
# 1. Get project info
curl -s 'https://api.revenuecat.com/v2/projects' \
  -H 'Authorization: Bearer $API_KEY'

# 2. List all apps (find app IDs)
curl -s 'https://api.revenuecat.com/v2/projects/$PROJECT_ID/apps' \
  -H 'Authorization: Bearer $API_KEY'

# 3. List all products
curl -s 'https://api.revenuecat.com/v2/projects/$PROJECT_ID/products' \
  -H 'Authorization: Bearer $API_KEY'

# 4. List offerings
curl -s 'https://api.revenuecat.com/v2/projects/$PROJECT_ID/offerings' \
  -H 'Authorization: Bearer $API_KEY'

# 5. List packages in default offering
curl -s 'https://api.revenuecat.com/v2/projects/$PROJECT_ID/offerings/$OFFERING_ID/packages' \
  -H 'Authorization: Bearer $API_KEY'

# 6. Check products attached to a package
curl -s 'https://api.revenuecat.com/v2/projects/$PROJECT_ID/packages/$PACKAGE_ID/products' \
  -H 'Authorization: Bearer $API_KEY'
```

---

## Creating Products

### App Store Product (iOS)
```bash
curl -s -X POST 'https://api.revenuecat.com/v2/projects/$PROJECT_ID/products' \
  -H 'Authorization: Bearer $API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "app_id": "$APP_STORE_APP_ID",
    "store_identifier": "pro_monthly_subscription",
    "display_name": "Pro Monthly",
    "type": "subscription"
  }'
```

### Play Store Product (Android)
```bash
# Note: store_identifier must be "subscriptionId:basePlanId"
curl -s -X POST 'https://api.revenuecat.com/v2/projects/$PROJECT_ID/products' \
  -H 'Authorization: Bearer $API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "app_id": "$PLAY_STORE_APP_ID",
    "store_identifier": "pro_monthly_subscription:p1m",
    "display_name": "Pro Monthly",
    "type": "subscription"
  }'
```

---

## Managing Packages

### Attach Product to Package
```bash
curl -s -X POST 'https://api.revenuecat.com/v2/projects/$PROJECT_ID/packages/$PACKAGE_ID/actions/attach_products' \
  -H 'Authorization: Bearer $API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "products": [
      {"product_id": "$PRODUCT_ID", "eligibility_criteria": "all"}
    ]
  }'
```

### Attach Multiple Products at Once
```bash
curl -s -X POST 'https://api.revenuecat.com/v2/projects/$PROJECT_ID/packages/$PACKAGE_ID/actions/attach_products' \
  -H 'Authorization: Bearer $API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "products": [
      {"product_id": "$PRODUCT_ID_1", "eligibility_criteria": "all"},
      {"product_id": "$PRODUCT_ID_2", "eligibility_criteria": "all"}
    ]
  }'
```

### Detach Product from Package
```bash
curl -s -X POST 'https://api.revenuecat.com/v2/projects/$PROJECT_ID/packages/$PACKAGE_ID/actions/detach_products' \
  -H 'Authorization: Bearer $API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "product_ids": ["$PRODUCT_ID"]
  }'
```

---

## Managing Entitlements

### List Entitlements
```bash
curl -s 'https://api.revenuecat.com/v2/projects/$PROJECT_ID/entitlements' \
  -H 'Authorization: Bearer $API_KEY'
```

### Attach Product to Entitlement
```bash
curl -s -X POST 'https://api.revenuecat.com/v2/projects/$PROJECT_ID/entitlements/$ENTITLEMENT_ID/actions/attach_products' \
  -H 'Authorization: Bearer $API_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "product_ids": ["$PRODUCT_ID_1", "$PRODUCT_ID_2"]
  }'
```

---

## Customer Operations

### Get Customer Info
```bash
curl -s 'https://api.revenuecat.com/v2/projects/$PROJECT_ID/customers/$CUSTOMER_ID' \
  -H 'Authorization: Bearer $API_KEY'
```

### Get Customer Subscriptions
```bash
curl -s 'https://api.revenuecat.com/v2/projects/$PROJECT_ID/customers/$CUSTOMER_ID/subscriptions' \
  -H 'Authorization: Bearer $API_KEY'
```

### Get Sandbox Customer (Testing)
```bash
curl -s 'https://api.revenuecat.com/v2/projects/$PROJECT_ID/customers/$CUSTOMER_ID?environment=sandbox' \
  -H 'Authorization: Bearer $API_KEY'
```

---

## Full Setup Example (New Project)

```bash
# Variables
API_KEY="sk_xxxxxx"
PROJECT_ID="<YOUR_PROJECT_ID>"
APP_STORE_APP_ID="<YOUR_APP_STORE_APP_ID>"
PLAY_STORE_APP_ID="<YOUR_PLAY_STORE_APP_ID>"

# 1. Create Entitlement
curl -s -X POST "https://api.revenuecat.com/v2/projects/$PROJECT_ID/entitlements" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"lookup_key": "pro", "display_name": "Pro Access"}'

# 2. Create Offering
curl -s -X POST "https://api.revenuecat.com/v2/projects/$PROJECT_ID/offerings" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"lookup_key": "default", "display_name": "Default Offering", "is_current": true}'

# 3. Create Monthly Package (get offering_id from step 2)
curl -s -X POST "https://api.revenuecat.com/v2/projects/$PROJECT_ID/offerings/$OFFERING_ID/packages" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"lookup_key": "$rc_monthly", "display_name": "Monthly subscription", "position": 1}'

# 4. Create Yearly Package
curl -s -X POST "https://api.revenuecat.com/v2/projects/$PROJECT_ID/offerings/$OFFERING_ID/packages" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"lookup_key": "$rc_annual", "display_name": "Yearly subscription", "position": 0}'

# 5. Create App Store Products
curl -s -X POST "https://api.revenuecat.com/v2/projects/$PROJECT_ID/products" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"app_id\": \"$APP_STORE_APP_ID\", \"store_identifier\": \"pro_monthly_subscription\", \"display_name\": \"Pro Monthly\", \"type\": \"subscription\"}"

curl -s -X POST "https://api.revenuecat.com/v2/projects/$PROJECT_ID/products" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"app_id\": \"$APP_STORE_APP_ID\", \"store_identifier\": \"pro_yearly_subscription\", \"display_name\": \"Pro Yearly\", \"type\": \"subscription\"}"

# 6. Create Play Store Products
curl -s -X POST "https://api.revenuecat.com/v2/projects/$PROJECT_ID/products" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"app_id\": \"$PLAY_STORE_APP_ID\", \"store_identifier\": \"pro_monthly_subscription:p1m\", \"display_name\": \"Pro Monthly\", \"type\": \"subscription\"}"

curl -s -X POST "https://api.revenuecat.com/v2/projects/$PROJECT_ID/products" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"app_id\": \"$PLAY_STORE_APP_ID\", \"store_identifier\": \"pro_yearly_subscription:p1y\", \"display_name\": \"Pro Yearly\", \"type\": \"subscription\"}"

# 7. Attach Products to Packages (get product_ids and package_ids from previous steps)
# ... attach each product to its respective package

# 8. Attach Products to Entitlement
# ... attach all products to the "pro" entitlement
```

---

## Troubleshooting

### "Product not available" Error
1. Check products exist for both App Store and Play Store
2. Verify products are attached to packages
3. Ensure store_identifier matches App Store Connect / Google Play Console

### Play Store Product Creation Fails
- Use format: `subscriptionId:basePlanId`
- Example: `pro_monthly_subscription:p1m`

### "Incompatible product already attached"
- Each app can only have one product per package
- Detach old product before attaching new one
