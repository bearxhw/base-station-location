# 逻辑地址子库REST备用接口使用说明

## 1. 适用条件

REST只在下游不能使用只读数据库连接时启用，例如跨网络域、外部系统或数据库隔离要求较高的部署。

内部可信服务默认使用数据库视图。REST单页最多5,000条是HTTP响应保护，不代表逻辑子库最多5,000条；调用方可以持续使用游标遍历全部记录。

Base URL、网关认证和TLS要求由05号环境配置交接单填写。当前Demo接口本身不包含生产级身份认证，生产必须置于统一API网关或增加服务间认证。

## 2. 游标分页接口

```http
POST /api/v1/address-scopes/{scopeId}/items
Content-Type: application/json
```

### 2.1 路径参数

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `scopeId` | UUID string | 是 | 从MQ事件或定位返回值取得 |

### 2.2 请求体

```json
{
  "requestId": "page-request-001",
  "sourceTypes": ["BUILDING", "AOI", "POI", "LOI"],
  "pageSize": 1000,
  "cursor": null
}
```

| 字段 | 类型 | 必填 | 规则 |
|---|---|---|---|
| `requestId` | string | 是 | 调用方生成的追踪ID |
| `sourceTypes` | string[] | 否 | 空或不传表示四种类型全部读取 |
| `pageSize` | integer | 否 | 1～5000，默认100 |
| `cursor` | string | 否 | 第一页为空；后续页原样回传上页`nextCursor` |

`sourceTypes`不区分输入大小写，但建议统一使用大写枚举。

### 2.3 成功响应

```json
{
  "success": true,
  "code": "OK",
  "message": "success",
  "requestId": "page-request-001",
  "data": {
    "addressScopeRef": {
      "scopeId": "992488ca-d04e-4ad3-bd62-f4eb8a82ef47",
      "locationResolutionId": "ad018390-9628-4d02-be61-999173461b14",
      "locationResolutionVersion": 1,
      "inventoryVersion": "REAL_AI_TILED_1M_V1",
      "scopeStatus": "READY"
    },
    "items": [
      {
        "inventoryId": "0002415c-5e4f-4237-a17b-e1ea342fcb4b",
        "sourceType": "POI",
        "sourceId": "poi_3:10001",
        "standardName": "凯丽花园(公交站)",
        "shortName": "凯丽花园",
        "fullAddress": "示例市示例区示例路",
        "aoiName": "凯丽花园",
        "roadName": "示例路",
        "hitLevel": "SEARCH_AREA",
        "longitude": 118.33,
        "latitude": 23.35
      }
    ],
    "nextCursor": "djE6MDAwMjQxNW...",
    "hasMore": true,
    "warnings": [
      "LOGICAL_SCOPE_IS_QUERY_ONLY_NO_ADDRESS_COPY",
      "USE_NEXT_CURSOR_UNTIL_HAS_MORE_IS_FALSE"
    ]
  },
  "metadata": {}
}
```

### 2.4 遍历算法

```text
cursor = null
do:
    response = POST items(scopeId, pageSize, cursor)
    处理 response.data.items
    cursor = response.data.nextCursor
while response.data.hasMore == true
```

规则：

- `cursor`是不透明值，调用方不得Base64解码、拼接或修改；
- 下一页必须保持相同`scopeId`和`sourceTypes`；
- `hasMore=false`时`nextCursor`为空，遍历结束；
- 业务处理成功后再保存已完成游标；
- 若整个消费任务重试，可以从已提交的最后游标继续；下游业务仍应按`inventoryId`幂等。

## 3. 范围内进一步过滤接口

当调用方需要按地址名称或类型进一步筛选时使用：

```http
POST /api/v1/location/resolutions/{locationResolutionId}/address-scope/query
Content-Type: application/json
```

```json
{
  "requestId": "filter-request-001",
  "locationResolutionVersion": 1,
  "inventoryVersion": "REAL_AI_TILED_1M_V1",
  "queryText": "科技园",
  "sourceTypes": ["AOI", "POI"],
  "limit": 100,
  "includeExactCount": false
}
```

| 字段 | 规则 |
|---|---|
| `locationResolutionVersion` | 必须等于句柄事件中的版本 |
| `inventoryVersion` | 必须等于句柄事件中的库存版本 |
| `queryText` | 可空；服务会做小写、空白和标点归一化 |
| `sourceTypes` | 可空，枚举同分页接口 |
| `limit` | 1～5000，默认100 |
| `includeExactCount` | 默认false；只有统计和审计场景才设true |

该接口返回筛选结果，不用于完整稳定遍历。需要全部结果时使用`/{scopeId}/items`游标接口。

## 4. 错误响应

当前实现中的参数、句柄和有效期错误统一返回HTTP 400：

```json
{
  "success": false,
  "code": "INVALID_REQUEST",
  "message": "Address scope not found or expired: 992488ca-d04e-4ad3-bd62-f4eb8a82ef47",
  "requestId": "服务器生成的错误追踪ID",
  "data": null,
  "metadata": {}
}
```

常见错误：

| 错误信息 | 原因 | 处理 |
|---|---|---|
| `scopeId is required` | 句柄为空 | 修正调用参数 |
| `Address scope not found or expired` | 不存在或已过期 | 停止使用并告警 |
| `pageSize must be between 1 and 5000` | 单页大小非法 | 调整范围 |
| `sourceTypes contains unsupported value` | 类型枚举非法 | 使用四种规定枚举 |
| `cursor is invalid or expired` | 游标被修改或格式错误 | 从已确认的上一页游标恢复 |

HTTP 409和`VERSION_CONFLICT`用于定位版本冲突，不是正常逻辑子库分页错误。

## 5. 调用示例

```powershell
$scopeId = '992488ca-d04e-4ad3-bd62-f4eb8a82ef47'
$body = @{
  requestId = 'page-request-001'
  sourceTypes = @('AOI', 'POI')
  pageSize = 1000
  cursor = $null
} | ConvertTo-Json

Invoke-RestMethod `
  -Method Post `
  -Uri "$env:ADDRESS_SCOPE_BASE_URL/api/v1/address-scopes/$scopeId/items" `
  -ContentType 'application/json' `
  -Body $body
```

生产调用还必须携带网关要求的服务身份或Token，具体Header不能由Demo文档假定，以环境交接单为准。

## 6. 机器契约

完整路径、请求和响应Schema以项目根目录[OpenAPI](../../contracts/openapi.yaml)为准。Markdown样例用于理解，代码生成和契约测试必须使用OpenAPI文件。
