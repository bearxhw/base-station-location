# 基站定位与逻辑地址子库

本仓库整理自 WJX 的基站定位交付工程，保存定位服务部署模板、PostGIS
数据结构与迁移、RabbitMQ 事件契约、下游联调文档和真实地址环境的独立部署模块。
运行数据、数据库转储、离线镜像、已构建 JAR 和真实凭据不进入版本库。

> 当前仓库包含服务外围工程和接口契约，不包含 `location-service.jar` 的
> Java 源码。部署时需要从原构建工程提供 JAR，或在 `compose.yaml` 中配置等价服务镜像。

## 仓库结构

- `contracts/`：定位 REST OpenAPI 契约。
- `db/`：PostGIS 迁移、演示数据和查询核验脚本。
- `docs/逻辑子库接入交付包/`：热词与地址机器人下游接入材料。
- `migration/`：环境间备份与恢复脚本。
- `deployments/real-environment/`：与模拟环境隔离的真实地址部署变体。
- 根目录脚本与 `compose.yaml`：环境初始化、启动、验证和端到端冒烟。

## 安全说明

仓库只提供 `.env.example`。首次部署运行 `bootstrap-env.sh` 生成随机口令，
不要把生成的 `.env`、数据库转储或运行目录提交到 Git。

---

## 原部署说明

当前部署环境：

| 环境 | 主机 | 部署目录 | 状态 |
|---|---|---|---|
| 原联调环境 | `192.168.173.167` | `/home/twai/wjx/location` | 保持运行 |
| 压测准备环境 | `192.168.169.144` | `/home/twai/wjx/base-station-location` | 已在线迁移并验证 |

144的完整迁移证据见[144压测环境迁移与联调说明](144压测环境迁移与联调说明.md)。

## 1. 组件和端口

| 组件 | 容器 | 对外地址 | 用途 |
|---|---|---|---|
| 定位服务 | `wjx-location-service` | `192.168.173.167:18080` | 接收基站坐标，生成定位范围和`scopeId` |
| PostGIS | `wjx-location-postgis` | `192.168.173.167:15432` | 保存完整地址库和逻辑子库视图；下游只读直连 |
| RabbitMQ | `wjx-location-rabbitmq` | `192.168.173.167:5672` | 向两个下游通知`scopeId`及最终定位范围已就绪 |

144使用相同端口：定位HTTP `192.168.169.144:18080`、PostGIS `192.168.169.144:15432`、RabbitMQ `192.168.169.144:5672`。两个环境的`.env`、数据库卷和RabbitMQ卷互相独立。

RabbitMQ管理端口只绑定服务器回环地址`127.0.0.1:15672`，不直接暴露到局域网。

## 2. 启动与检查

```bash
cd /home/twai/wjx/location
bash bootstrap-env.sh
bash start.sh
bash status.sh
bash verify.sh
bash e2e-smoke.sh
```

144执行相同命令前切换到：

```bash
cd /home/twai/wjx/base-station-location
```

`bootstrap-env.sh`会保留已有配置，只补充缺少的随机密码，并把`.env`权限设为`600`。`start.sh`会启动PostGIS和RabbitMQ、创建下游账号与MQ拓扑，然后启动定位服务。`e2e-smoke.sh`会产生一条测试定位记录，并验证双队列与两个只读数据库账号。

停止服务但保留数据卷：

```bash
bash stop.sh
```

## 3. 定位接口

```bash
curl -X POST http://192.168.173.167:18080/api/v1/location/resolutions \
  -H 'Content-Type: application/json' \
  -d '{
    "requestId":"location-example-001",
    "sessionId":"call-example-001",
    "alarmId":"alarm-example-001",
    "sourceType":"CTI_COORDINATE",
    "baseStationCoordinate":{
      "longitude":116.33,
      "latitude":39.92,
      "coordinateSystem":"WGS84",
      "accuracyMeters":30
    },
    "radiusMeters":5000
  }'
```

响应中的`data.addressScopeRef.scopeId`就是本次逻辑子库句柄，`scopeStatus`说明范围内是否存在地址：`READY`表示至少一条，`EMPTY`表示句柄有效但范围为空。定位事务提交后，Outbox会把同一个句柄事件分别投递到热词服务队列和地址机器人队列。

## 4. RabbitMQ拓扑

| 项目 | 值 |
|---|---|
| 协议 | AMQP 0-9-1 |
| Virtual host | `/location` |
| Exchange | `location.address-scope.v1`（durable direct） |
| Routing key | `address.scope.ready.v1` |
| 热词队列 | `location.address-scope.hotword.v1` |
| 地址机器人队列 | `location.address-scope.addressbot.v1` |
| 死信Exchange | `location.address-scope.dlx.v1` |
| 死信队列 | 主队列名称加`.dlq` |

消息是持久化CloudEvent，包含`eventId/sessionId/alarmId/scopeId/scopeStatus/版本/查询路径`以及小体量`locationScope`。`locationScope`给出最终WGS84参考中心、半径、范围类型和定位方式；不发送完整地址数组。

## 5. 下游直接访问完整数据库

下游默认使用独立账号连接：

- 热词服务：`.env`中的`LOCATION_DB_HOTWORD_USER/PASSWORD`；
- 地址机器人：`.env`中的`LOCATION_DB_ADDRESSBOT_USER/PASSWORD`。

两个账号均可`SELECT`当前完整业务数据库的`dispatch_assist`和`ai`两个schema，包括真实表形状的`ai.aoi_*`、`ai.poi_*`、`ai.loi_road`，但不能执行写入和DDL。

收到消息后先检查`scopeStatus`；`EMPTY`无需查询明细即可结束。`READY`按本服务当前条件查询，例如：

```sql
SELECT inventory_id,
       source_type,
       source_id,
       standard_name,
       full_address,
       aoi_name,
       road_name,
       longitude,
       latitude
FROM dispatch_assist.logical_address_scope_item
WHERE scope_id = CAST(:scopeId AS uuid)
  AND source_type IN ('AOI', 'POI')
  AND (standard_name ILIKE :namePattern
       OR full_address ILIKE :namePattern)
ORDER BY inventory_id;
```

如需补充原始属性，可继续用`source_table/source_record_id`关联查询`ai`下的AOI、POI、LOI原表。下游访问的是同一套完整数据库，不会为每个电话新建数据库或复制数据。REST仅在下游不能直连数据库时作为备用方式。

## 6. 账号交接

服务地址、vhost、交换机和队列名可直接交给下游；账号密码只从服务器`.env`经安全渠道分别交接，不写进代码、文档或MQ消息。查看管理界面时先建立SSH隧道：

```bash
ssh -L 15672:127.0.0.1:15672 twai@192.168.173.167
```

随后访问`http://127.0.0.1:15672`。

## 7. 运维与联调核验

```bash
# 只读检查服务、容器、双队列和最新Outbox，不产生新来电
bash verify-deployment.sh

# 模拟一次CTI坐标来电，验证HTTP、Outbox、双队列和双数据库账号
bash e2e-smoke.sh
```

两个脚本均从服务器本地`.env`读取凭据，不输出密码。

## 8. 迁移说明

目录内的PostGIS与RabbitMQ离线包是ARM64镜像，只适用于167同架构服务器；迁移到x86_64服务器时必须重新获取amd64基础镜像并构建，不能加载ARM包。在线数据迁移使用`migration/backup-source.sh`和`migration/restore-target.sh`，重新生成`.env`，将数据库和MQ端口限制在业务网段，并把密码迁入生产密钥管理系统。数据卷名称分别为`wjx-location-postgis-data`和`wjx-location-rabbitmq-data`。
