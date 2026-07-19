from __future__ import annotations

import json
import os
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from typing import Any

from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import FileResponse, JSONResponse, Response
from starlette.routing import Mount, Route
from starlette.staticfiles import StaticFiles

from .config import (
    config_warnings,
    load_config,
    normalize_protocol,
    preserve_masked_secrets,
    redact_config,
    safe_int,
    save_config,
)
from .db import db
from .db import pricing_summary
from .http_client import upstream
from .paths import STATIC_DIR
from .proxy import api_error, handle_anthropic_request, handle_chat_request, handle_responses_request
from .security import (
    SESSION_COOKIE,
    account_input,
    cleanup_sessions,
    create_session,
    destroy_session,
    has_admin_account,
    hash_password,
    is_admin_session,
    password_hash_kind,
    require_admin_auth,
    require_api_auth,
    verify_password,
)


async def _max_body(config: dict[str, Any] | None = None) -> int:
    config = config or await load_config()
    return safe_int(((config.get("concurrency") or {}).get("max_body_bytes")) or 8_000_000, 8_000_000, 1024, 512_000_000)


async def read_json(request: Request, max_body_bytes: int | None = None) -> dict[str, Any]:
    chunks: list[bytes] = []
    size = 0
    async for chunk in request.stream():
        size += len(chunk)
        if max_body_bytes is not None and size > max_body_bytes:
            raise ValueError(f"请求体过大，限制 {max_body_bytes} 字节")
        chunks.append(chunk)
    body = b"".join(chunks)
    try:
        data = json.loads(body.decode("utf-8") if body else "{}")
    except Exception:
        raise ValueError("请求体必须是有效的 JSON 对象")
    if not isinstance(data, dict):
        raise ValueError("请求体必须是有效的 JSON 对象")
    return data


def permission_response(exc: Exception) -> JSONResponse:
    message = str(exc) or "权限错误"
    status = 401 if "Token" in message or "API Key" in message or "用户名或密码" in message else 403
    return api_error(message, status)


async def index(_: Request) -> Response:
    return FileResponse(STATIC_DIR / "index.html")


async def auth_status(request: Request) -> Response:
    config = await load_config()
    authed = is_admin_session(request, config)
    account = config.get("admin_account") or {}
    kind = password_hash_kind(str(account.get("password_hash") or ""))
    payload = {
        "installed": has_admin_account(config),
        "authenticated": authed,
        "username": account.get("username", "") if authed else "",
        "password_hash_kind": kind if has_admin_account(config) else "",
    }
    if kind == "bcrypt":
        payload["warning"] = "检测到 PHP bcrypt 密码哈希，请删除 admin_account 后重新初始化管理员账号"
    return JSONResponse(payload)


async def setup_admin(request: Request) -> Response:
    config = await load_config()
    if has_admin_account(config):
        return api_error("初始化已完成，请使用管理员账号登录", 409)
    try:
        body = await read_json(request, await _max_body(config))
        username, password = account_input(body)
    except ValueError as exc:
        return api_error(str(exc), 400)
    config["admin_account"] = {
        "username": username,
        "password_hash": hash_password(password),
    }
    await save_config(config)
    sid = create_session(username)
    response = JSONResponse({"ok": True, "username": username}, status_code=201)
    response.set_cookie(SESSION_COOKIE, sid, httponly=True, samesite="lax", path="/")
    return response


async def login_admin(request: Request) -> Response:
    config = await load_config()
    if not has_admin_account(config):
        return api_error("请先完成初始化", 409)
    try:
        body = await read_json(request, await _max_body(config))
        username, password = account_input(body)
    except ValueError as exc:
        return api_error(str(exc), 400)
    account = config.get("admin_account") or {}
    stored_user = account.get("username") or ""
    password_hash = account.get("password_hash") or ""
    if stored_user != username or not verify_password(password, password_hash):
        # PHP bcrypt hash is not portable here; force reset guidance.
        if password_hash.startswith("$2y$") or password_hash.startswith("$2a$") or password_hash.startswith("$2b$"):
            return api_error("检测到 PHP bcrypt 密码哈希，请删除 data/config.json 中的 admin_account 后重新初始化，或使用 admin_tokens 管理", 401)
        return api_error("用户名或密码错误", 401)
    sid = create_session(username)
    response = JSONResponse({"ok": True, "username": username})
    response.set_cookie(SESSION_COOKIE, sid, httponly=True, samesite="lax", path="/")
    return response


async def logout_admin(request: Request) -> Response:
    destroy_session(request.cookies.get(SESSION_COOKIE))
    response = JSONResponse({"ok": True})
    response.delete_cookie(SESSION_COOKIE, path="/")
    return response


async def get_config(request: Request) -> Response:
    config = await load_config()
    try:
        await require_admin_auth(request, config)
    except PermissionError as exc:
        return permission_response(exc)
    safe = redact_config(config)
    safe["warnings"] = config_warnings(config)
    return JSONResponse(safe)


async def update_config(request: Request) -> Response:
    config = await load_config()
    try:
        await require_admin_auth(request, config)
        body = await read_json(request, await _max_body(config))
    except PermissionError as exc:
        return permission_response(exc)
    except ValueError as exc:
        return api_error(str(exc), 400)
    if not isinstance(body.get("providers"), dict):
        return api_error("配置必须包含 providers 对象")
    try:
        body = preserve_masked_secrets(body, config)
        saved = await save_config(body)
    except Exception as exc:
        return api_error(str(exc), 400)
    return JSONResponse({"ok": True, "warnings": config_warnings(saved)})


async def get_provider_secret(request: Request) -> Response:
    config = await load_config()
    try:
        await require_admin_auth(request, config)
    except PermissionError as exc:
        return permission_response(exc)
    provider_id = request.path_params["provider_id"]
    provider = (config.get("providers") or {}).get(provider_id)
    if not provider:
        return JSONResponse({"ok": False, "message": "提供商不存在"}, status_code=404)
    return JSONResponse({"ok": True, "api_key": provider.get("api_key") or ""})


async def update_provider(request: Request) -> Response:
    config = await load_config()
    try:
        await require_admin_auth(request, config)
        provider = await read_json(request, await _max_body(config))
    except PermissionError as exc:
        return permission_response(exc)
    except ValueError as exc:
        return api_error(str(exc), 400)
    provider_id = request.path_params["provider_id"]
    providers = config.setdefault("providers", {})
    existing = providers.get(provider_id) or {}
    if "*" in str(provider.get("api_key") or ""):
        provider["api_key"] = existing.get("api_key") or ""
    providers[provider_id] = provider
    try:
        await save_config(config)
    except Exception as exc:
        return api_error(str(exc), 400)
    return JSONResponse({"ok": True})


async def delete_provider(request: Request) -> Response:
    config = await load_config()
    try:
        await require_admin_auth(request, config)
    except PermissionError as exc:
        return permission_response(exc)
    provider_id = request.path_params["provider_id"]
    (config.get("providers") or {}).pop(provider_id, None)
    try:
        await save_config(config)
    except Exception as exc:
        return api_error(str(exc), 400)
    return JSONResponse({"ok": True})


async def update_mappings(request: Request) -> Response:
    config = await load_config()
    try:
        await require_admin_auth(request, config)
        body = await read_json(request, await _max_body(config))
    except PermissionError as exc:
        return permission_response(exc)
    except ValueError as exc:
        return api_error(str(exc), 400)
    except Exception:
        return api_error("请求体必须是有效的 JSON 对象", 400)
    if not isinstance(body, dict):
        return api_error("模型映射必须是对象", 400)
    config["model_mappings"] = body
    try:
        saved = await save_config(config)
    except Exception as exc:
        return api_error(str(exc), 400)
    return JSONResponse({"ok": True, "warnings": config_warnings(saved)})


async def test_connection(request: Request) -> Response:
    config = await load_config()
    try:
        await require_admin_auth(request, config)
        body = await read_json(request, await _max_body(config))
    except PermissionError as exc:
        return permission_response(exc)
    except ValueError as exc:
        return api_error(str(exc), 400)
    provider_id = body.get("provider_id") or ""
    provider = (config.get("providers") or {}).get(provider_id) if provider_id else body.get("provider")
    if not isinstance(provider, dict) or not provider.get("base_url"):
        return JSONResponse({"ok": False, "status": 0, "message": "缺少 Base URL"}, status_code=400)
    ptype = provider.get("type") or "openai"
    base = str(provider.get("base_url") or "").rstrip("/")
    if ptype == "ollama":
        url = base + "/api/tags"
    elif ptype == "anthropic" and not base.endswith("/v1"):
        url = base + "/v1/models"
    else:
        url = base + "/models"
    headers = {}
    if ptype == "anthropic":
        headers["x-api-key"] = provider.get("api_key") or ""
        headers["anthropic-version"] = "2023-06-01"
    elif provider.get("api_key"):
        headers["Authorization"] = f"Bearer {provider.get('api_key')}"
    try:
        resp = await upstream.request("GET", url, headers=headers)
        status = resp.status_code
        text = resp.text
    except Exception as exc:
        return JSONResponse({"ok": False, "status": 0, "message": str(exc)})
    ok = status < 400 or status in {404, 405}
    return JSONResponse(
        {
            "ok": ok,
            "status": status,
            "message": ("服务可达，但不支持测试端点" if status >= 400 else "连接成功") if ok else text[:200],
        }
    )


async def discover_models(request: Request) -> Response:
    config = await load_config()
    try:
        await require_admin_auth(request, config)
    except PermissionError as exc:
        return permission_response(exc)
    provider_id = request.path_params["provider_id"]
    provider = (config.get("providers") or {}).get(provider_id)
    if not provider:
        return JSONResponse({"ok": False, "message": "提供商不存在"}, status_code=404)
    ptype = provider.get("type") or "openai"
    base = str(provider.get("base_url") or "").rstrip("/")
    if ptype == "ollama":
        url = base + "/api/tags"
    elif ptype == "anthropic" and not base.endswith("/v1"):
        url = base + "/v1/models"
    else:
        url = base + "/models"
    headers = {}
    if ptype == "anthropic":
        headers["x-api-key"] = provider.get("api_key") or ""
        headers["anthropic-version"] = "2023-06-01"
    elif provider.get("api_key"):
        headers["Authorization"] = f"Bearer {provider.get('api_key')}"
    try:
        resp = await upstream.request("GET", url, headers=headers)
    except Exception as exc:
        return JSONResponse({"ok": False, "message": str(exc)})
    if resp.status_code >= 400:
        return JSONResponse({"ok": False, "message": resp.text[:200]})
    try:
        raw = resp.json()
    except Exception:
        return JSONResponse({"ok": False, "message": "无法解析模型列表"})
    items = raw.get("data") if isinstance(raw, dict) and "data" in raw else (
        raw.get("models") if isinstance(raw, dict) and "models" in raw else raw
    )
    models = []
    for item in items if isinstance(items, list) else []:
        if isinstance(item, dict):
            model_id = item.get("id") or item.get("name") or ""
        else:
            model_id = str(item)
        if model_id:
            models.append({"id": model_id, "name": model_id})
    return JSONResponse({"ok": True, "provider": provider_id, "models": models})


async def get_stats(request: Request) -> Response:
    config = await load_config()
    try:
        await require_admin_auth(request, config)
    except PermissionError as exc:
        return permission_response(exc)
    range_key = (request.query_params.get("range") or "24h").strip().lower()
    range_map = {
        "1h": timedelta(hours=1),
        "24h": timedelta(hours=24),
        "7d": timedelta(days=7),
        "30d": timedelta(days=30),
    }
    where_sql = ""
    params: list[Any] = []
    if range_key in range_map:
        cutoff = (datetime.now(timezone.utc) - range_map[range_key]).isoformat()
        where_sql = " WHERE timestamp >= ?"
        params.append(cutoff)
    summary = await db.fetchone(
        f"""
        SELECT COUNT(*) AS total_requests,
               COALESCE(SUM(input_tokens),0) AS total_input,
               COALESCE(SUM(output_tokens),0) AS total_output,
               COALESCE(SUM(total_tokens),0) AS total_tokens,
               COALESCE(AVG(latency_ms),0) AS avg_latency,
               COALESCE(SUM(CASE WHEN status='ok' THEN 1 ELSE 0 END),0) AS ok_count,
               COALESCE(SUM(CASE WHEN status='error' THEN 1 ELSE 0 END),0) AS error_count,
               COALESCE(SUM(cost_usd),0) AS total_cost
        FROM usage
        {where_sql}
        """,
        params,
    )
    providers = await db.fetchall(
        f"""
        SELECT provider, COUNT(*) AS count, SUM(total_tokens) AS tokens,
               SUM(cost_usd) AS total_cost, AVG(latency_ms) AS avg_latency
        FROM usage{where_sql} GROUP BY provider ORDER BY count DESC
        """,
        params,
    )
    models = await db.fetchall(
        f"""
        SELECT model, provider, COUNT(*) AS count,
               SUM(input_tokens) AS input_tokens,
               SUM(output_tokens) AS output_tokens,
               SUM(total_tokens) AS total_tokens,
               COALESCE(SUM(cost_usd),0) AS total_cost,
               AVG(latency_ms) AS avg_latency
        FROM usage{where_sql} GROUP BY model, provider ORDER BY total_cost DESC, count DESC
        """,
        params,
    )
    by_hour = await db.fetchall(
        f"""
        SELECT substr(timestamp, 1, 13) AS hour,
               COUNT(*) AS count,
               COALESCE(SUM(total_tokens),0) AS tokens,
               COALESCE(SUM(cost_usd),0) AS total_cost
        FROM usage{where_sql}
        GROUP BY substr(timestamp, 1, 13)
        ORDER BY hour ASC
        """,
        params,
    )
    recent = await db.fetchall(f"SELECT * FROM usage{where_sql} ORDER BY timestamp DESC LIMIT 50", params)
    model_pricing = []
    for row in models:
        model_id = row.get("model") or ""
        info = pricing_summary(config, model_id)
        row["pricing"] = info
        row["avg_cost_per_req"] = float(row.get("total_cost") or 0) / max(int(row.get("count") or 0), 1)
        model_pricing.append({"model": model_id, **info})
    return JSONResponse(
        {
            "summary": summary or {},
            "by_provider": providers,
            "by_model": models,
            "pricing": model_pricing,
            "by_hour": by_hour,
            "recent": recent,
        }
    )


async def get_logs(request: Request) -> Response:
    config = await load_config()
    try:
        await require_admin_auth(request, config)
    except PermissionError as exc:
        return permission_response(exc)
    try:
        page = max(1, int(request.query_params.get("page") or 1))
    except (TypeError, ValueError):
        page = 1
    try:
        per_page = max(1, min(100, int(request.query_params.get("per_page") or 30)))
    except (TypeError, ValueError):
        per_page = 30
    provider = (request.query_params.get("provider") or "").strip()
    status_filter = (request.query_params.get("status") or "").strip()
    where = []
    params: list[Any] = []
    if provider:
        where.append("provider = ?")
        params.append(provider)
    if status_filter == "success":
        where.append("status_code >= 200 AND status_code < 400")
    if status_filter == "error":
        where.append("status_code >= 400")
    where_sql = (" WHERE " + " AND ".join(where)) if where else ""
    total_row = await db.fetchone(f"SELECT COUNT(*) AS c FROM request_log{where_sql}", params)
    total = int((total_row or {}).get("c") or 0)
    pages = max(1, (total + per_page - 1) // per_page)
    page = min(page, pages)
    items = await db.fetchall(
        f"SELECT * FROM request_log{where_sql} ORDER BY timestamp DESC LIMIT ? OFFSET ?",
        params + [per_page, (page - 1) * per_page],
    )
    return JSONResponse(
        {
            "total": total,
            "page": page,
            "per_page": per_page,
            "pages": pages,
            "items": items,
        }
    )


async def clear_logs(request: Request) -> Response:
    config = await load_config()
    try:
        await require_admin_auth(request, config)
    except PermissionError as exc:
        return permission_response(exc)
    await db.execute("DELETE FROM request_log")
    return JSONResponse({"ok": True})


async def clear_stats(request: Request) -> Response:
    config = await load_config()
    try:
        await require_admin_auth(request, config)
    except PermissionError as exc:
        return permission_response(exc)
    await db.execute("DELETE FROM usage")
    return JSONResponse({"ok": True})


async def export_config(request: Request) -> Response:
    config = await load_config()
    try:
        await require_admin_auth(request, config)
    except PermissionError as exc:
        return permission_response(exc)
    return JSONResponse(redact_config(config))


async def import_config(request: Request) -> Response:
    config = await load_config()
    try:
        await require_admin_auth(request, config)
        body = await read_json(request, await _max_body(config))
    except PermissionError as exc:
        return permission_response(exc)
    except ValueError as exc:
        return api_error(str(exc), 400)
    if "providers" not in body:
        return api_error("缺少 providers 字段")
    try:
        body = preserve_masked_secrets(body, config)
        saved = await save_config(body)
    except Exception as exc:
        return api_error(str(exc), 400)
    return JSONResponse({"ok": True, "warnings": config_warnings(saved)})


async def list_models(request: Request) -> Response:
    config = await load_config(mutable=False)
    try:
        await require_api_auth(request, config)
    except PermissionError as exc:
        return permission_response(exc)
    items = []
    for alias, mapping in (config.get("model_mappings") or {}).items():
        pid = mapping.get("provider") or ""
        if config.get("force_default_provider") and pid != config.get("default_provider"):
            continue
        provider = (config.get("providers") or {}).get(pid)
        if provider and provider.get("enabled"):
            items.append(
                {
                    "id": alias,
                    "object": "model",
                    "created": 0,
                    "owned_by": pid,
                    "provider_name": provider.get("name") or pid,
                    "provider_base_url": provider.get("base_url") or "",
                    "upstream_model": mapping.get("model") or alias,
                    "protocol": normalize_protocol(mapping.get("protocol") or "", provider),
                }
            )
    return JSONResponse({"object": "list", "data": items})


async def chat_completions(request: Request) -> Response:
    config = await load_config(mutable=False)
    try:
        await require_api_auth(request, config)
        body = await read_json(request, await _max_body(config))
    except PermissionError as exc:
        return permission_response(exc)
    except ValueError as exc:
        return api_error(str(exc), 400)
    return await handle_chat_request(config, body)


async def responses(request: Request) -> Response:
    config = await load_config(mutable=False)
    try:
        await require_api_auth(request, config)
        body = await read_json(request, await _max_body(config))
    except PermissionError as exc:
        return permission_response(exc)
    except ValueError as exc:
        return api_error(str(exc), 400)
    return await handle_responses_request(config, body)


async def messages(request: Request) -> Response:
    config = await load_config(mutable=False)
    try:
        await require_api_auth(request, config)
        body = await read_json(request, await _max_body(config))
    except PermissionError as exc:
        message = str(exc) or "权限错误"
        status = 401 if "Token" in message or "API Key" in message else 403
        return api_error(message, status, "anthropic")
    except ValueError as exc:
        return api_error(str(exc), 400, "anthropic")
    return await handle_anthropic_request(config, body)


async def health(request: Request) -> Response:
    config = await load_config(mutable=False)
    # Expose detailed health only to local/admin clients when bound beyond localhost.
    try:
        host = str(os.environ.get("HOST") or ((config.get("server") or {}).get("host") or "127.0.0.1")).strip()
        if host not in {"127.0.0.1", "::1", "localhost"}:
            await require_admin_auth(request, config)
    except PermissionError as exc:
        return permission_response(exc)
    return JSONResponse(
        {
            "ok": True,
            "service": "ai-api-switch-py",
            "upstream": upstream.stats,
            "db": db.stats,
            "concurrency": config.get("concurrency") or {},
        }
    )


async def metrics(request: Request) -> Response:
    config = await load_config(mutable=False)
    try:
        host = str(os.environ.get("HOST") or ((config.get("server") or {}).get("host") or "127.0.0.1")).strip()
        if host not in {"127.0.0.1", "::1", "localhost"}:
            await require_admin_auth(request, config)
    except PermissionError as exc:
        return permission_response(exc)
    return JSONResponse(
        {
            "upstream": upstream.stats,
            "db": db.stats,
        }
    )


@asynccontextmanager
async def lifespan(app: Starlette):
    config = await load_config()
    concurrency = config.get("concurrency") or {}
    await db.start(write_queue_size=int(concurrency.get("write_queue_size") or 1000))
    await upstream.start()
    try:
        cleanup_sessions()
    except Exception:
        pass
    try:
        yield
    finally:
        await upstream.stop()
        await db.stop()


routes = [
    Route("/", index),
    Route("/api/health", health, methods=["GET"]),
    Route("/api/metrics", metrics, methods=["GET"]),
    Route("/api/auth/status", auth_status, methods=["GET"]),
    Route("/api/setup", setup_admin, methods=["POST"]),
    Route("/api/login", login_admin, methods=["POST"]),
    Route("/api/logout", logout_admin, methods=["POST"]),
    Route("/api/config", get_config, methods=["GET"]),
    Route("/api/config", update_config, methods=["POST"]),
    Route("/api/providers/{provider_id}/secret", get_provider_secret, methods=["GET"]),
    Route("/api/providers/{provider_id}", update_provider, methods=["POST"]),
    Route("/api/providers/{provider_id}", delete_provider, methods=["DELETE"]),
    Route("/api/mappings", update_mappings, methods=["POST"]),
    Route("/api/test", test_connection, methods=["POST"]),
    Route("/api/discover/{provider_id}", discover_models, methods=["POST"]),
    Route("/api/stats", get_stats, methods=["GET"]),
    Route("/api/logs", get_logs, methods=["GET"]),
    Route("/api/logs/clear", clear_logs, methods=["POST"]),
    Route("/api/stats/clear", clear_stats, methods=["POST"]),
    Route("/api/config/export", export_config, methods=["GET"]),
    Route("/api/config/import", import_config, methods=["POST"]),
    Route("/v1/models", list_models, methods=["GET"]),
    Route("/v1/chat/completions", chat_completions, methods=["POST"]),
    Route("/v1/responses", responses, methods=["POST"]),
    Route("/v1/messages", messages, methods=["POST"]),
    Mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static"),
]

app = Starlette(routes=routes, lifespan=lifespan)
