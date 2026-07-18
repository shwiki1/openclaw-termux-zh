# AI API Switch Python（异步高并发版）

基于 `ai-api-switch-php` 二次开发的 Python 版本，使用 **Starlette + Uvicorn + httpx + aiosqlite**。

默认地址：`http://127.0.0.1:9999/`

## 并发优化

- 单进程异步事件循环，适合大量 SSE 长连接与 I/O 等待
- 共享 `httpx.AsyncClient` 连接池（keepalive）
- 上游并发信号量 `concurrency.max_upstream`（默认 64）
- SQLite 写队列异步落库，避免请求路径阻塞
- 可选多进程：`WORKERS=2 bash start.sh`（Termux 通常建议 `WORKERS=1`）

## 启动 / 停止

```bash
bash start.sh
bash stop.sh
```

环境变量：

- `PORT` 默认 `9999`
- `HOST` 默认 `127.0.0.1`
- `WORKERS` 默认 `1`
- `LIMIT_CONCURRENCY` 覆盖 uvicorn 并发上限

## 配置迁移

```bash
python3 scripts/migrate_from_php.py
```

注意：PHP 的 `password_hash()`（bcrypt `$2y$`）无法直接用于本版登录校验。迁移后请删除 `data/config.json` 里的 `admin_account`，重新打开管理页完成初始化；或配置 `admin_tokens` / `auth_tokens`。

## 已实现接口

- `POST /v1/chat/completions`
- `POST /v1/responses`
- `POST /v1/messages`
- `GET /v1/models`
- 管理接口 `/api/*`（配置、提供商、映射、测试、发现模型、统计、日志、导入导出、登录）

## 协议规则

与 PHP 版一致：

- 映射 `protocol` 表示**对外协议**
- `openai` 只能走 `/v1/chat/completions`
- `responses` 只能走 `/v1/responses`
- `anthropic` 只能走 `/v1/messages`
- 提供商 `type` 表示上游协议，本地会做必要转换

## 目录

```
api2py/
  app/               # 异步服务代码
  data/config.json   # 配置
  public/static/     # 管理前端
  server.py          # 启动入口
  start.sh / stop.sh
```


## 健康检查

- `GET /api/health`
- `GET /api/metrics`

返回上游 inflight、DB 写队列、错误计数等。

## 并发建议

- Termux 默认 `WORKERS=1`（单进程 async）
- `WORKERS>1` 会多进程各自持有连接池和 DB writer，仅在有明确隔离需求时使用
- `concurrency.max_body_bytes` 默认 8MB，防止超大请求体
- 未精确映射的模型可走 `prefix_routes`（最长前缀匹配）
