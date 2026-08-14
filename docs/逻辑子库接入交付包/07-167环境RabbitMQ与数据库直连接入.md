# 167环境RabbitMQ与数据库直连接入

## 1. 当前状态

截至2026-08-05，定位组件已部署在`192.168.173.167`的`/home/twai/wjx/location`，定位服务、PostGIS和RabbitMQ三个容器均已启动并通过健康检查。

| 能力 | 地址 | 对外状态 |
|---|---|---|
| 定位HTTP | `http://192.168.173.167:18080` | 局域网可访问 |
| PostGIS | `192.168.173.167:15432/dispatch_assist` | 局域网可访问；独立只读账号 |
| RabbitMQ AMQP | `192.168.173.167:5672`，vhost `/location` | 局域网可访问；独立消费账号 |
| RabbitMQ管理界面 | `127.0.0.1:15672` | 仅服务器本机；需SSH隧道 |

## 2. 下游交接内容

热词服务获得：

- 队列`location.address-scope.hotword.v1`；
- MQ账号引用`LOCATION_RABBITMQ_HOTWORD_USER/PASSWORD`；
- DB账号引用`LOCATION_DB_HOTWORD_USER/PASSWORD`。

地址机器人获得：

- 队列`location.address-scope.addressbot.v1`；
- MQ账号引用`LOCATION_RABBITMQ_ADDRESSBOT_USER/PASSWORD`；
- DB账号引用`LOCATION_DB_ADDRESSBOT_USER/PASSWORD`。

实际密码保存在服务器`.env`并且文件权限为`600`。文档、代码和MQ消息均不保存密码；实施人员通过安全渠道分别交付。

## 3. 默认读取方式

下游收到消息后先读取`data.addressScopeRef.scopeStatus`。`EMPTY`直接记录并ACK；`READY`取`scopeId`，使用本服务的业务条件直接查询。当前新消息还包含`data.locationScope`：地址机器人可用其中的WGS84中心和半径计算候选距离或排序；热词服务可忽略。该元数据不得用于改变半径或重新生成另一套子库，精确范围以`scopeId`为准。以下是地址机器人按名称线索查询AOI/POI的示例：

```sql
SELECT inventory_id, source_type, source_id,
       standard_name, full_address, aoi_name, road_name,
       longitude, latitude
FROM dispatch_assist.logical_address_scope_item
WHERE scope_id = CAST(:scopeId AS uuid)
  AND source_type IN ('AOI', 'POI')
  AND (standard_name ILIKE :namePattern
       OR full_address ILIKE :namePattern)
ORDER BY inventory_id;
```

REST仅在下游无法直连数据库时使用。不得把无条件读取、传输和渲染全部35,985条地址作为每通电话的固定步骤。热词服务确实需要遍历全部地址词面时，应查询`logical_address_scope_hotword_item`并使用JDBC流式游标。

两个账号还可只读访问`dispatch_assist`和`ai`完整业务schema，因此能按`source_table/source_record_id`继续查询AOI、POI、LOI原表；不能写入、建表或执行管理操作。167中的`ai`表是兼容真实源表结构的联调模拟数据，不是生产真实地址库存。完整源表清单、关联键和查询SQL见[08-AOI、POI原表回查与字段映射说明](08-AOI-POI原表回查与字段映射说明.md)。

## 4. 实测证据

端到端脚本`/home/twai/wjx/location/e2e-smoke.sh`于2026-08-05执行通过：

| 项目 | 结果 |
|---|---:|
| API坐标到`scopeId` | 最终版本重启后79.591 ms；预热后9.765 ms |
| Outbox创建到RabbitMQ confirm | 重启后1,065.278 ms；预热后279.737 ms |
| 坐标请求到两个队列消息均可直接读取 | 预热后409 ms |
| 完整双队列、双DB校验 | 预热后658 ms |
| 测试`scopeId`命中总数 | 35,985 |
| AOI / BUILDING / LOI / POI | 1,410 / 1,847 / 5,956 / 26,772 |
| Outbox状态/重试次数 | `PUBLISHED` / 0 |
| 两个消息体满足CloudEvent契约且包含同一`scopeId` | 通过 |
| 两个数据库只读账号返回总数 | 一致 |

最新测试句柄：`74905ac6-b1de-4909-9d85-a325e3a2383d`。Outbox默认每1秒轮询一次，因此请求落在不同轮询相位时延迟会波动；预热实测Broker确认279.737 ms、两个队列可直接读到消息409 ms。该数据用于联调追踪，不构成生产SLA。

### 4.1 V16空范围与查询性能整改验证

2026-08-05部署包SHA-256为`C81A677FA10962C9A7BCCF652F09C9B3EE23C49B35043C2A3CEB22FFC8D6793E`，服务重建后完成以下验证：

| 用例 | 结果 |
|---|---|
| READY请求 | `scopeId=a2871b13-fa5e-4c46-bf5d-a3fba43612ee`，HTTP耗时153.923 ms，实际命中35,985条 |
| EMPTY请求 | `scopeId=61416cee-8eea-4f48-b415-6d3203bd9f21`，HTTP耗时12.644 ms，实际命中0条，包含`EMPTY_ADDRESS_SCOPE` |
| 状态一致性 | HTTP响应、`logical_address_scope_summary`和`address.scope.ready.v1`事件一致 |
| READY短路判断 | GiST索引，数据库执行0.333 ms，找到首条即停止 |
| EMPTY短路判断 | GiST索引，数据库执行0.340 ms，不做完整`COUNT(*)` |
| 业务条件查询 | 35,985条范围内筛选AOI/POI和名称，取前100条执行46.883 ms |
| 自动化测试 | 当前累计54项通过、0失败 |

上述HTTP耗时是单次功能证据，不是并发统计值。业务方日常应按条件获取需要的记录；只有热词服务确需遍历全部词面时才使用窄字段视图和流式游标。

### 4.2 地址机器人定位范围元数据验证

2026-08-06部署包SHA-256为`D40C03B1E86A91DB7F703E47EC66BBA68E0EA239DB043CDAE6EFF8352D3FEC4E`。端到端脚本以CTI坐标和2公里半径发起一次真实请求，验证结果如下：

| 项目 | 结果 |
|---|---|
| 最新`scopeId` | `a4bf1dc4-f343-40a8-b2f4-b27610db5bee` |
| API坐标到句柄 | 11.249 ms |
| Outbox到Broker确认 | 750.519 ms，`PUBLISHED`、重试0次 |
| 热词下游 | 在线消费者的投递计数增加，证明新事件已被实时接收 |
| 地址机器人下游 | 队列消息体可读取，CloudEvent、`scopeId`和`locationScope`字段全部通过校验 |
| 双账号逻辑子库查询 | 均为35,985条；AOI 1,410、BUILDING 1,847、LOI 5,956、POI 26,772 |
| 全部验收动作 | 1,467 ms；包含MQ轮询、消息校验、双账号完整计数和分类统计 |
| 自动化测试 | 54项通过、0失败 |

两个下游使用同一事件内容、不同队列和不同账号，不互相等待。地址机器人队列当前没有在线消费者时，消息会持久化积压，接入后可继续读取；这不影响热词服务正常消费。

## 5. 联调命令

服务器运维检查：

```bash
cd /home/twai/wjx/location
bash status.sh
bash verify.sh
bash e2e-smoke.sh
```

管理界面通过SSH隧道访问：

```bash
ssh -L 15672:127.0.0.1:15672 twai@192.168.173.167
```

## 6. 生产迁移

当前是联调环境。迁移生产时应保留相同事件与数据库契约，替换主机、凭据和库存数据；限制`5672/15432`到下游业务网段，并补充TLS、RabbitMQ高可用、PostGIS备份恢复、连接数与消息积压监控。
