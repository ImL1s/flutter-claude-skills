---
name: api-contract-testing
description: Flutter/Dart API 契約測試與逆向工程 API 驗證。當需要對第三方 API 做整合測試、驗證 JSON 回應格式、建立 API 契約、快照回歸測試、或使用 api_contract/pact_dart/json_serializable 做契約驗證時使用。觸發關鍵字："API 契約", "contract test", "API 測試", "整合測試", "API 格式驗證", "逆向 API", "JSONP parse", "response validation", "API regression"。
---

# API Contract Testing for Flutter/Dart

系統化的「逆向 API → 建立契約 → 整合測試 → 回歸守護」流程。

## 方法論名稱

| 方法 | 說明 | 適用場景 |
|------|------|---------|
| **Consumer-Driven Contract Testing (CDCT)** | 消費者定義期望格式，對 API 驗證 | 微服務、自有 API |
| **Characterization Testing** | 先跑真實系統記錄行為，用測試鎖住行為 | 未文件化的第三方 API |
| **Reverse-Engineered API Contract Testing** | 逆向工程 API → 建立契約 → 驗證 → 回歸 | 爬蟲、第三方 API |

## 四階段流程

```
1. Discovery    → 逆向工程 API 格式（curl / 參考開源專案 / 抓包）
2. Contract     → 用 Model + @JsonKey / @ApiContractSchema 定義契約
3. Verification → 對真實 API 跑整合測試驗證契約
4. Regression   → 快照保存 + CI 回歸守護
```

---

## Dart/Flutter 工具選擇指南

### 🏆 推薦方案：三層防護

```
編譯期 ─── json_serializable / freezed（@JsonKey 鎖定欄位名）
Runtime ─── api_contract（validate() 驗證回應格式）
CI/CD  ─── @Tags(['integration']) 整合測試（對真實 API 跑）
```

### 套件比較

| 套件 | 版本 | 用途 | 是否需要 Provider 配合 | 推薦度 |
|------|------|------|----------------------|--------|
| **`api_contract`** + **`api_contract_generator`** | 0.2.1 | Runtime 契約驗證 + codegen | ❌ 不需要 | ⭐⭐⭐ 首推 |
| **`json_serializable`** + **`json_annotation`** | 6.x | 編譯期 JSON ↔ Model 映射 | ❌ | ⭐⭐⭐ 必用 |
| **`freezed`** | 2.x | 同上 + immutable + union types | ❌ | ⭐⭐⭐ |
| **`pact_dart`** | 0.8.0 | Pact FFI v3 完整 CDCT | ✅ 需要 provider 端驗證 | ⭐⭐ 微服務用 |
| **`http_mock_adapter`** | 0.6.x | Dio mock adapter（手動定義） | ❌ | ⭐⭐ 輔助 |
| **`json_schema`** | — | JSON Schema 驗證 | ❌ | ⭐ |

---

## 實作步驟

### Step 1: 安裝依賴

```yaml
# pubspec.yaml
dependencies:
  api_contract: ^0.2.1
  json_annotation: ^4.9.0

dev_dependencies:
  api_contract_generator: ^0.2.0
  json_serializable: ^6.8.0
  build_runner: ^2.4.13
  test: any
```

### Step 2: Model 加上雙重契約（json_serializable + api_contract）

```dart
import 'package:json_annotation/json_annotation.dart';
import 'package:api_contract/api_contract.dart';
import 'package:api_contract_generator/api_contract_generator.dart';

part 'family_mart_store.g.dart';

/// 全家門市 — 來自 api.map.com.tw
@JsonSerializable()
@ApiContractSchema(mode: ContractMode.lenient, version: '1.0')
class FamilyMartStore {
  FamilyMartStore({
    required this.name,
    required this.longitude,
    required this.latitude,
    required this.address,
    required this.id,
    this.tel,
  });

  @JsonKey(name: 'NAME')
  final String name;

  @JsonKey(name: 'px')
  final double longitude;

  @JsonKey(name: 'py')
  final double latitude;

  @JsonKey(name: 'addr')
  final String address;

  @JsonKey(name: 'pkey')
  final String id;

  @JsonKey(name: 'TEL')
  @optional
  final String? tel;

  factory FamilyMartStore.fromJson(Map<String, dynamic> json) =>
      _$FamilyMartStoreFromJson(json);

  Map<String, dynamic> toJson() => _$FamilyMartStoreToJson(this);
}
```

**好處：**
- `@JsonKey(name: 'NAME')` → 編譯期欄位名鎖死，打錯名不會 silent fail
- `@ApiContractSchema` → 自動生成 `familyMartStoreContract`，runtime 驗證

### Step 3: 生成程式碼

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Step 4: 整合測試（對真實 API）

```dart
@Tags(['integration'])
import 'package:test/test.dart';
import 'package:dio/dio.dart';

void main() {
  late Dio dio;

  setUpAll(() {
    dio = Dio(BaseOptions(connectTimeout: Duration(seconds: 10)));
  });

  tearDownAll(() => dio.close());

  group('FamilyMart API Contract', () {
    test('familyShop.aspx → FamilyMartStore contract valid', () async {
      final response = await dio.get(
        'http://api.map.com.tw/net/familyShop.aspx',
        queryParameters: {
          'searchType': 'ShopList',
          'type': '',
          'city': '台北市',
          'area': '',
          'road': '',
          'fun': 'showStoreList',
          'key': YOUR_API_KEY,
        },
      );

      // 1. 解析 JSONP
      final jsonList = parseJsonp(response.data as String);
      expect(jsonList, isNotEmpty);

      // 2. 契約驗證（runtime）
      for (final json in jsonList.take(5)) {
        final result = familyMartStoreContract.validate(json);
        result.throwIfInvalid(); // CI 中會直接失敗
      }

      // 3. Model 解析驗證（compile-time 契約）
      final store = FamilyMartStore.fromJson(jsonList.first);
      expect(store.name, isNotEmpty);
      expect(store.latitude, greaterThan(20)); // 台灣緯度
      expect(store.longitude, greaterThan(100)); // 台灣經度
    });
  });
}
```

### Step 5: 快照保存（離線回歸）

```dart
test('snapshot: 保存 API 回應供離線測試', () async {
  final response = await dio.get(apiUrl, queryParameters: params);

  // 存為 fixture
  final file = File('test/fixtures/familymart_shoplist_snapshot.json');
  file.writeAsStringSync(jsonEncode(parseJsonp(response.data)));

  print('✅ 快照已保存: ${file.path} (${file.lengthSync()} bytes)');
});
```

然後單元測試用快照：

```dart
test('FamilyMartStore.fromJson with fixture', () {
  final fixture = File('test/fixtures/familymart_shoplist_snapshot.json');
  final jsonList = jsonDecode(fixture.readAsStringSync()) as List;

  for (final json in jsonList) {
    final store = FamilyMartStore.fromJson(json as Map<String, dynamic>);
    expect(store.name, isNotEmpty);
    // 不需要網路！
  }
});
```

### Step 6: CI/CD 整合

```yaml
# .github/workflows/test.yml
jobs:
  unit-tests:
    steps:
      - run: dart test --exclude-tags integration

  contract-tests:
    steps:
      - run: dart test --tags integration
    # 可選：只在 schedule 或手動觸發時跑
    # 因為真實 API 可能有 rate limit
```

### Step 7: Global 配置（app 初始化）

```dart
void main() {
  ApiContractConfig.setup(
    onViolation: ViolationBehavior.throwInCI,  // CI 中抛異常
    enableInRelease: false,                     // 生產環境零開銷
    logPrefix: '[Contract]',
  );
  runApp(MyApp());
}
```

---

## pact_dart 用法（適合微服務/自有 API）

> **注意：** `pact_dart` 需要 API 提供方配合驗證 pact file。
> **對第三方 API（如 7-11、全家）不適用**，因為你無法讓對方跑 provider verification。

```dart
import 'package:pact_dart/pact_dart.dart';

final pact = PactMockService('MyApp', 'MyBackendAPI');

pact
  .newInteraction()
  .given('stores exist')
  .uponReceiving('a request for nearby stores')
  .withRequest('GET', '/api/stores', query: {'lat': '25.03', 'lng': '121.56'})
  .willRespondWith(200, body: {
    'stores': PactMatchers.EachLike([
      {
        'id': PactMatchers.SomethingLike('store_001'),
        'name': PactMatchers.SomethingLike('台北101店'),
        'lat': PactMatchers.DecimalLike(25.033),
        'lng': PactMatchers.DecimalLike(121.564),
      }
    ]),
  });

pact.run(secure: false);
// ... 用 repository 發請求 ...
pact.writePactFile();
pact.reset();
```

安裝：
```bash
dart pub add --dev pact_dart
flutter pub run pact_dart:install  # 安裝 FFI 庫
```

---

## JSONP 解析工具函式

很多台灣本土 API 回傳 JSONP（如全家、部分政府 API）：

```dart
/// 解析 JSONP 回應，回傳 JSON List
List<Map<String, dynamic>> parseJsonp(String response) {
  // 去掉 callback 包裝: callback([...])
  final match = RegExp(r'\w+\(\s*([\s\S]*)\s*\);?').firstMatch(response);
  if (match == null || match.group(1) == null) {
    throw FormatException('Invalid JSONP response');
  }

  final jsonStr = match.group(1)!;
  final decoded = jsonDecode(jsonStr);

  if (decoded is List) {
    return decoded.cast<Map<String, dynamic>>();
  } else if (decoded is Map<String, dynamic>) {
    return [decoded];
  }
  throw FormatException('Unexpected JSONP content type: ${decoded.runtimeType}');
}
```

---

## 常見陷阱與檢查清單

### 欄位映射陷阱
- [ ] API 欄位名是否和你的 Model 一致？（台灣 API 常用 `NAME` 不是 `name`）
- [ ] 座標是 `double` 還是 `String`？（全家 `px`/`py` 是 double！）
- [ ] 回應是 JSON 還是 JSONP？（`callback([...])` 包裝）
- [ ] 回應是 JSON 還是 XML？（7-11 emap 是 XML）
- [ ] `int` 欄位會不會偶爾回 `String`？（如數量 `"5"` vs `5`）
- [ ] 回應在某些條件下會回 HTML 嗎？（如全家 ShopLunchBox API）

### 測試隔離
- [ ] 整合測試加 `@Tags(['integration'])`
- [ ] CI 預設跑 `--exclude-tags integration`
- [ ] 真實 API 測試設定合理的 timeout（`timeout: Timeout(Duration(seconds: 30))`）
- [ ] 考慮 API rate limit，不要在 CI 每次 push 都跑

### 回歸守護
- [ ] 首次跑完存 fixture 快照
- [ ] 定期（週/月）跑整合測試更新快照
- [ ] 快照變更時 review diff（API 格式是否真的改了？）

---

## 決策流程圖

```
你要測的 API 是誰的？
├── 自有 API / 微服務 → pact_dart (CDCT)
└── 第三方 API（無法控制）
    ├── 有文件化的 spec → json_schema 驗證
    └── 未文件化（逆向工程）
        ├── Step 1: curl / 參考開源專案 → Discovery
        ├── Step 2: json_serializable @JsonKey → 編譯期契約
        ├── Step 3: api_contract @ApiContractSchema → Runtime 契約
        ├── Step 4: @Tags(['integration']) 真實 API 測試 → Verification
        └── Step 5: fixture 快照 → Regression Guard
```
