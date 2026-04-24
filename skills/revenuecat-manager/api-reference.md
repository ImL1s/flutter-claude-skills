# RevenueCat REST API v2 - Complete Reference

Base URL: `https://api.revenuecat.com/v2`

## Authentication

```
Authorization: Bearer sk_xxxxxxxxxxxxxx
Content-Type: application/json
```

---

## Projects

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/projects` | List all projects (developer-level access) |

---

## Apps

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/projects/{project_id}/apps` | List all apps |
| POST | `/projects/{project_id}/apps` | Create app |
| GET | `/projects/{project_id}/apps/{app_id}` | Get app |
| PUT | `/projects/{project_id}/apps/{app_id}` | Update app |
| DELETE | `/projects/{project_id}/apps/{app_id}` | Delete app |

### Create App Request Body
```json
{
  "name": "App Name",
  "type": "app_store" | "play_store" | "amazon" | "stripe" | "rc_billing"
}
```

---

## Products

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/projects/{project_id}/products` | List all products |
| POST | `/projects/{project_id}/products` | Create product |
| GET | `/projects/{project_id}/products/{product_id}` | Get product |
| PUT | `/projects/{project_id}/products/{product_id}` | Update product |
| DELETE | `/projects/{project_id}/products/{product_id}` | Delete product |

### Create Product Request Body
```json
{
  "app_id": "app_xxxxx",
  "store_identifier": "product_id_in_store",
  "display_name": "Display Name",
  "type": "subscription" | "one_time"
}
```

**Play Store subscription format:**
```json
{
  "store_identifier": "subscription_id:base_plan_id"
}
```

---

## Offerings

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/projects/{project_id}/offerings` | List offerings |
| POST | `/projects/{project_id}/offerings` | Create offering |
| GET | `/projects/{project_id}/offerings/{offering_id}` | Get offering |
| PUT | `/projects/{project_id}/offerings/{offering_id}` | Update offering |
| DELETE | `/projects/{project_id}/offerings/{offering_id}` | Delete offering |

### Create Offering Request Body
```json
{
  "lookup_key": "default",
  "display_name": "Default Offering",
  "is_current": true
}
```

---

## Packages

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/projects/{project_id}/offerings/{offering_id}/packages` | List packages |
| POST | `/projects/{project_id}/offerings/{offering_id}/packages` | Create package |
| GET | `/projects/{project_id}/packages/{package_id}` | Get package |
| PUT | `/projects/{project_id}/packages/{package_id}` | Update package |
| DELETE | `/projects/{project_id}/packages/{package_id}` | Delete package |

### Create Package Request Body
```json
{
  "lookup_key": "$rc_monthly" | "$rc_annual" | "$rc_weekly" | "custom_key",
  "display_name": "Monthly Subscription",
  "position": 0
}
```

### Standard Package Lookup Keys
- `$rc_monthly` - Monthly
- `$rc_annual` - Annual/Yearly
- `$rc_weekly` - Weekly
- `$rc_two_month` - Two Month
- `$rc_three_month` - Three Month
- `$rc_six_month` - Six Month
- `$rc_lifetime` - Lifetime

---

## Package Products (Attach/Detach)

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/projects/{project_id}/packages/{package_id}/products` | List products in package |
| POST | `/projects/{project_id}/packages/{package_id}/actions/attach_products` | Attach products |
| POST | `/projects/{project_id}/packages/{package_id}/actions/detach_products` | Detach products |

### Attach Products Request Body
```json
{
  "products": [
    {
      "product_id": "prod_xxxxx",
      "eligibility_criteria": "all" | "google_sdk_lt_6" | "google_sdk_ge_6"
    }
  ]
}
```

### Detach Products Request Body
```json
{
  "product_ids": ["prod_xxxxx", "prod_yyyyy"]
}
```

---

## Entitlements

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/projects/{project_id}/entitlements` | List entitlements |
| POST | `/projects/{project_id}/entitlements` | Create entitlement |
| GET | `/projects/{project_id}/entitlements/{entitlement_id}` | Get entitlement |
| PUT | `/projects/{project_id}/entitlements/{entitlement_id}` | Update entitlement |
| DELETE | `/projects/{project_id}/entitlements/{entitlement_id}` | Delete entitlement |

### Create Entitlement Request Body
```json
{
  "lookup_key": "pro",
  "display_name": "Pro Access"
}
```

---

## Entitlement Products

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/projects/{project_id}/entitlements/{entitlement_id}/products` | List products |
| POST | `/projects/{project_id}/entitlements/{entitlement_id}/actions/attach_products` | Attach products |
| POST | `/projects/{project_id}/entitlements/{entitlement_id}/actions/detach_products` | Detach products |

### Attach Products to Entitlement
```json
{
  "product_ids": ["prod_xxxxx", "prod_yyyyy"]
}
```

---

## Customers

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/projects/{project_id}/customers/{customer_id}` | Get customer info |
| GET | `/projects/{project_id}/customers/{customer_id}/subscriptions` | Get subscriptions |
| GET | `/projects/{project_id}/customers/{customer_id}/active_entitlements` | Get active entitlements |
| GET | `/projects/{project_id}/customers/{customer_id}/purchases` | Get purchases |
| PUT | `/projects/{project_id}/customers/{customer_id}/attributes` | Set attributes |

### Query Parameters
- `environment`: `production` | `sandbox`

---

## Subscriptions

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/projects/{project_id}/subscriptions/{subscription_id}` | Get subscription details |

---

## Purchases

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/projects/{project_id}/purchases` | List all purchases |
| GET | `/projects/{project_id}/purchases/{purchase_id}` | Get purchase details |

---

## Response Format

### Success (List)
```json
{
  "object": "list",
  "items": [...],
  "next_page": null | "token",
  "url": "https://api.revenuecat.com/v2/..."
}
```

### Success (Single Object)
```json
{
  "object": "product",
  "id": "prod_xxxxx",
  "created_at": 1234567890,
  ...
}
```

### Error
```json
{
  "object": "error",
  "type": "error_type",
  "message": "Error description",
  "doc_url": "https://errors.rev.cat/...",
  "retryable": false
}
```

---

## Error Types

| Type | Description |
|------|-------------|
| `resource_missing` | Resource not found (404) |
| `invalid_request_error` | Bad request parameters (400) |
| `unprocessable_entity_error` | Business logic error (422) |
| `authentication_error` | Invalid API key (401) |
| `rate_limit_error` | Too many requests (429) |

---

## Rate Limits

- ~60 requests/minute (variable)
- Headers:
  - `RevenueCat-Rate-Limit-Current-Usage`
  - `RevenueCat-Rate-Limit-Current-Limit`
- Implement exponential backoff for 429 errors
