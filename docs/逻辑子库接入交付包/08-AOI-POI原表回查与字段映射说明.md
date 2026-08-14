# AOI、POI原表回查与字段映射说明

版本：V1.1  
适用对象：动态热词加载服务、地址机器人、数据库实施人员  
适用方式：下游收到`scopeId`后，通过只读数据库连接查询逻辑子库及AOI、POI源表

## 1. 先说结论

`dispatch_assist.logical_address_scope_item`不是AOI、POI原表的完整副本。它只统一提供范围筛选结果、公共名称、地址、类型、代表点以及源记录定位信息。

下游需要原表专有字段时，应执行两步查询：

1. 使用`scope_id`查询`logical_address_scope_item`，确定哪些源记录属于本次逻辑子库；
2. 使用返回的`source_table + source_record_id`关联对应的`ai.aoi_* / ai.poi_* / ai.loi_road`源表。

```text
MQ事件中的scopeId
        ↓
logical_address_scope_item：确定范围内记录
        ↓
source_table + source_record_id：确定源表和源主键
        ↓
ai.aoi_* / ai.poi_* / ai.loi_road：读取完整业务字段
```

MQ传递`scopeId`及小体量`locationScope`，不传完整地址数组、原表整行数据或数据库凭据。

## 2. 当前167联调环境说明

数据库地址：`192.168.173.167:15432/dispatch_assist`  
可读Schema：`dispatch_assist`、`ai`  
凭据：通过环境交接单和安全渠道分别提供，禁止写入代码、文档或MQ消息。

截至2026-08-05，167环境已经创建以下源表兼容结构并装载模拟数据：

| 表 | 当前行数 | 主要用途 |
|---|---:|---|
| `ai.aoi_1` | 2,607 | 行政区划或地址层级父节点 |
| `ai.aoi_2` | 2,607 | 上层AOI |
| `ai.aoi_3` | 1,270 | 园区、小区等细粒度AOI |
| `ai.aoi_3_parent_ref` | 6,350 | AOI-3与AOI-2多父关系 |
| `ai.aoi_3_entrance_exit` | 314 | AOI出入口 |
| `ai.poi_1` | 5,081 | 建筑物 |
| `ai.poi_1_building_special` | 5,081 | 建筑高度、楼层、用途、消防救援口等属性 |
| `ai.poi_1_entrance_exit` | 0 | 建筑出入口；当前模拟源样例为空表 |
| `ai.poi_2` | 15,243 | 建筑楼层 |
| `ai.poi_3` | 73,665 | 单位、房间等细粒度POI |
| `ai.loi_road` | 16,377 | 道路空间对象 |

这些数据用于联调和方案验证，表结构兼容当前取得的真实`ods7alm.ai`样例契约，但数据不是生产真实AOI、POI库存。生产迁移必须替换为真实数据，并重新验证字段、坐标系、层级完整性、数据量和查询性能。

两个下游只读角色均已获得上述表的`SELECT`权限。如果数据库客户端只显示`dispatch_assist`，应刷新元数据并展开`ai` Schema；也可以直接使用带Schema的全限定表名，例如`ai.poi_3`。

## 3. 逻辑子库与源表映射

只有具备可用于空间筛选的对象会直接进入统一地址读模型。父节点、楼层、扩展属性和出入口通过源表关联补充。

| `source_type` | `source_table`实际值 | `source_record_id`对应字段 | 直接候选含义 |
|---|---|---|---|
| `AOI` | `ai.aoi_2` | `aoi_2.aoi_id` | 上层AOI |
| `AOI` | `ai.aoi_3` | `aoi_3.aoi_id` | 园区、小区等AOI |
| `BUILDING` | `ai.poi_1` | `poi_1.building_id` | 建筑物 |
| `POI` | `ai.poi_3` | `poi_3.poi_id` | 单位、房间等POI |
| `LOI` | `ai.loi_road` | `loi_road.road_id` | 道路 |

以下表不会单独成为逻辑子库候选，需要通过上述记录继续关联：

| 非直接候选表 | 关联方式 |
|---|---|
| `ai.aoi_1` | `aoi_2.area_id → aoi_1.area_id`，或`aoi_3.area_id → aoi_1.area_id` |
| `ai.aoi_3_parent_ref` | `aoi_3.aoi_id → aoi_3_parent_ref.aoi_3_id` |
| `ai.aoi_3_entrance_exit` | `aoi_3.aoi_id → aoi_3_entrance_exit.aoi_id` |
| `ai.poi_1_building_special` | `poi_1.building_id → poi_1_building_special.building_id` |
| `ai.poi_1_entrance_exit` | `poi_1.building_id → poi_1_entrance_exit.building_id` |
| `ai.poi_2` | `poi_1.building_id → poi_2.building_id` |
| `ai.poi_3`的建筑和楼层 | `poi_3.building_id → poi_1.building_id`；`poi_3.floor_id → poi_2.floor_id` |

`source_id`是便于展示和跨系统传递的组合标识，例如`ai.poi_3:POI0001`；数据库关联应优先使用已经拆分好的`source_table`和`source_record_id`，不要由下游再次解析`source_id`字符串。

## 4. 标准处理步骤

### 4.1 第一步：查看本次逻辑子库有哪些源记录

```sql
SELECT inventory_id,
       source_type,
       source_table,
       source_record_id,
       standard_name,
       full_address,
       hit_level,
       longitude,
       latitude
FROM dispatch_assist.logical_address_scope_item
WHERE scope_id = CAST(:scopeId AS uuid)
ORDER BY inventory_id;
```

该查询返回的记录已经通过PostGIS空间索引和`ST_Intersects`精确范围判断。下游不需要再次传入基站坐标或重新计算圆形范围。

### 4.2 第二步：按照固定表映射回查

下游应根据`source_table`走固定SQL分支，不要把消息内容直接拼成动态SQL。所有查询都必须保留`scope_id = :scopeId`条件，保证回查对象属于本次逻辑子库。

## 5. AOI完整信息查询

### 5.1 查询AOI-2及行政父节点

```sql
SELECT item.scope_id,
       item.hit_level,
       aoi.*,
       area.area_code AS parent_area_code,
       area.area_name AS parent_area_name,
       area.addrlevel_id AS parent_addrlevel_id
FROM dispatch_assist.logical_address_scope_item item
JOIN ai.aoi_2 aoi
  ON item.source_table = 'ai.aoi_2'
 AND aoi.aoi_id = item.source_record_id
LEFT JOIN ai.aoi_1 area
  ON area.area_id = aoi.area_id
 AND COALESCE(area.is_deleted, FALSE) = FALSE
WHERE item.scope_id = CAST(:scopeId AS uuid)
  AND aoi.is_deleted = FALSE;
```

### 5.2 查询AOI-3及全部AOI-2父节点

```sql
SELECT item.scope_id,
       item.hit_level,
       child.*,
       relation.aoi_2_id,
       parent.aoi_name AS parent_aoi_name
FROM dispatch_assist.logical_address_scope_item item
JOIN ai.aoi_3 child
  ON item.source_table = 'ai.aoi_3'
 AND child.aoi_id = item.source_record_id
LEFT JOIN ai.aoi_3_parent_ref relation
  ON relation.aoi_3_id = child.aoi_id
 AND relation.is_deleted = FALSE
LEFT JOIN ai.aoi_2 parent
  ON parent.aoi_id = relation.aoi_2_id
 AND parent.is_deleted = FALSE
WHERE item.scope_id = CAST(:scopeId AS uuid)
  AND child.is_deleted = FALSE;
```

一个AOI-3可以对应多个AOI-2父节点，因此该查询允许同一个AOI-3返回多行。这不是重复数据，而是源表中的多父关系。需要AOI出入口时，再按`child.aoi_id = ai.aoi_3_entrance_exit.aoi_id`查询。

## 6. 建筑物完整信息查询

```sql
SELECT item.scope_id,
       item.hit_level,
       building.*,
       special.met_buildingarea,
       special.met_height,
       special.met_upfloors,
       special.met_downfloors,
       special.buildusage_id,
       special.build_type_id,
       special.fire_rescue_access,
       special.sensitive_target
FROM dispatch_assist.logical_address_scope_item item
JOIN ai.poi_1 building
  ON item.source_table = 'ai.poi_1'
 AND building.building_id = item.source_record_id
LEFT JOIN ai.poi_1_building_special special
  ON special.building_id = building.building_id
 AND special.is_deleted = FALSE
WHERE item.scope_id = CAST(:scopeId AS uuid)
  AND building.is_deleted = FALSE;
```

建筑出入口是一对多关系，建议单独查询，避免与建筑、楼层、POI同时连接造成结果行数成倍增加：

```sql
SELECT entrance.*
FROM dispatch_assist.logical_address_scope_item item
JOIN ai.poi_1_entrance_exit entrance
  ON item.source_table = 'ai.poi_1'
 AND entrance.building_id = item.source_record_id
WHERE item.scope_id = CAST(:scopeId AS uuid)
  AND entrance.is_deleted = FALSE;
```

## 7. POI、楼层、建筑和AOI层级查询

```sql
SELECT item.scope_id,
       item.hit_level,
       poi.*,
       floor.floor_name,
       floor.floor_typename,
       floor.relative_height,
       building.building_name,
       building.address_name AS building_address,
       aoi.aoi_name
FROM dispatch_assist.logical_address_scope_item item
JOIN ai.poi_3 poi
  ON item.source_table = 'ai.poi_3'
 AND poi.poi_id = item.source_record_id
LEFT JOIN ai.poi_2 floor
  ON floor.floor_id = poi.floor_id
 AND floor.is_deleted = FALSE
LEFT JOIN ai.poi_1 building
  ON building.building_id = poi.building_id
 AND building.is_deleted = FALSE
LEFT JOIN ai.aoi_3 aoi
  ON aoi.aoi_id = poi.aoi_id
 AND aoi.is_deleted = FALSE
WHERE item.scope_id = CAST(:scopeId AS uuid)
  AND poi.is_deleted = FALSE;
```

该SQL返回逻辑范围内POI的原始字段，并补充所属楼层、建筑和AOI信息。下游负责根据自身业务选择字段，不需要把全部列长期加载到内存。

## 8. 道路完整信息查询

```sql
SELECT item.scope_id,
       item.hit_level,
       road.*
FROM dispatch_assist.logical_address_scope_item item
JOIN ai.loi_road road
  ON item.source_table = 'ai.loi_road'
 AND road.road_id = item.source_record_id
WHERE item.scope_id = CAST(:scopeId AS uuid)
  AND road.is_deleted = FALSE;
```

## 9. 数据一致性边界

逻辑子库通过`inventory_version`冻结空间候选版本，但AOI、POI源表仍可能被源系统更新。当前联调环境中源表和统一地址读模型由同一次模拟数据同步生成，能够正常回查。

生产环境必须满足以下要求：

1. 定位数据库中存在可读的真实AOI、POI、LOI源表，或者存在字段兼容的只读副本、同步表或外部表；
2. 生成`address_inventory`时必须保留准确的`source_table`和`source_record_id`；
3. 源数据删除或改主键前，至少保留覆盖逻辑子库TTL的可回查版本；
4. 如果业务要求“原表字段也严格按创建逻辑子库时冻结”，必须建设版本化源表或把必要字段写入版本化读模型，不能直接读取持续变化的当前源表；
5. 真实数据同步完成后，应检查逻辑子库记录回查源表的缺失率，目标为0。

如果目标环境只部署`address_inventory`和统一视图，没有任何AOI、POI源表或源数据访问接口，那么下游只能取得统一视图已有公共字段，无法还原楼层、房间、建筑属性、AOI多父关系等原表专有信息。此时必须先补充源表同步、只读副本或源数据明细API，不能通过MQ补传完整库存规避问题。

## 10. 下游实现约束

- 消费MQ后只保存和传递`scopeId`，不缓存数据库密码；
- 数据库查询必须使用下游专属只读账号；
- 查询统一视图必须带`scope_id`等值条件；
- 原表回查使用固定映射SQL，禁止直接拼接未经校验的`source_table`；
- 大逻辑子库应按`inventory_id`游标分批读取，建议每批500至2,000条；
- 一对多关系建议分开查询或聚合，避免多张一对多表同时连接造成笛卡尔放大；
- 热词加载只读取所需名称和地址字段，词面去重、Top-K、权重及ASR装载仍由热词服务负责；
- 地址机器人可按业务需要继续读取AOI层级、建筑属性、楼层、房间和出入口。

## 11. 联调验收SQL

检查当前账号是否能看到源表：

```sql
SELECT table_schema, table_name
FROM information_schema.tables
WHERE table_schema = 'ai'
ORDER BY table_name;
```

检查逻辑子库各来源表数量：

```sql
SELECT source_table, COUNT(*) AS item_count
FROM dispatch_assist.logical_address_scope_item
WHERE scope_id = CAST(:scopeId AS uuid)
GROUP BY source_table
ORDER BY source_table;
```

检查逻辑子库记录是否能回查源表，以`ai.poi_3`为例：

```sql
SELECT COUNT(*) AS missing_count
FROM dispatch_assist.logical_address_scope_item item
LEFT JOIN ai.poi_3 poi
  ON poi.poi_id = item.source_record_id
WHERE item.scope_id = CAST(:scopeId AS uuid)
  AND item.source_table = 'ai.poi_3'
  AND poi.poi_id IS NULL;
```

预期`missing_count = 0`。AOI、建筑物和道路应按本说明中的映射执行相同检查。
