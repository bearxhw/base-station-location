# 167 真实地址环境

该目录在 `192.168.173.167` 上提供与现有模拟环境完全隔离的真实地址定位服务。不会停止、重启或写入 `/home/twai/wjx/location` 模拟环境。

## 环境边界

| 项目 | 模拟环境 | 真实环境 |
|---|---|---|
| 服务目录 | `/home/twai/wjx/location` | `/home/twai/wjx/location-real` |
| REST | `:18080` | `:18082` |
| PostGIS | `:15432` | `:15433` |
| RabbitMQ | `:5672` | `:5673` |
| vhost | `/location` | `/location-real` |
| 数据版本 | `REALISTIC_AI_SOURCE_V1` | `ODS7ALM_AI_REAL_20260810_V1` |

真实环境使用独立容器、网络和 Docker 数据卷。原始表保留在 `ai.*`，统一空间检索读模型位于 `dispatch_assist.address_inventory`。逻辑子库仍是 `scopeId` 指向的查询范围，不复制地址数据。

## 启动与状态

```bash
cd /home/twai/wjx/location-real
bash start.sh
bash status.sh
```

首次启动需要 `runtime/real-ai-source.dump`；后续重启复用独立真实数据卷。所有口令只保存在权限为 `600` 的 `.env`，文档不记录口令。

下游获得 `scopeId` 后，使用真实环境只读账号连接 `192.168.173.167:15433`，按 `scope_id` 查询：

```sql
SELECT *
FROM dispatch_assist.logical_address_scope_source_ref_item
WHERE scope_id = :scope_id;
```

通过 `source_table` 与 `source_record_id` 可继续回查同库中的 `ai.aoi_2`、`ai.aoi_3`、`ai.poi_1`、`ai.poi_3`、`ai.loi_road` 原始字段。
