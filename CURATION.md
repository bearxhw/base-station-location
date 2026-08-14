# 整理说明

## 来源

- 主部署：`/home/twai/wjx/location`
- 真实地址环境：`/home/twai/wjx/location-real`
- 整理日期：2026-08-15

## 保留内容

- OpenAPI、JSON Schema 与消息示例；
- PostGIS 建表、迁移、索引、演示数据和核验 SQL；
- Docker Compose 与环境变量模板；
- RabbitMQ、数据库只读账号初始化和端到端验证脚本；
- 逻辑地址子库接入、迁移和联调文档；
- 真实地址环境与模拟环境不同的部署实现。

## 排除内容

- `runtime/` 中的数据库备份、离线镜像和运行状态；
- `location-service.jar` 及其备份；
- 真实 `.env`、SQLite 文件、日志和压缩交付包；
- 重复的服务器现场副本。

原始目录保持不变，本仓库是用于长期维护的精选副本。
