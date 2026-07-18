#!/usr/bin/env python3
"""AI API Switch Python async server entrypoint."""

from __future__ import annotations

import os
import sys
from pathlib import Path

import uvicorn

APP_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(APP_ROOT))

from app.config import load_config  # noqa: E402


def env_int(name: str, default: int, minimum: int = 1) -> int:
    try:
        value = int(os.environ.get(name) or default)
    except (TypeError, ValueError):
        value = default
    return max(minimum, value)


def safe_int_value(value, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def main() -> None:
    import asyncio

    config = asyncio.run(load_config())
    server = config.get("server") or {}
    host = os.environ.get("HOST") or server.get("host") or "127.0.0.1"
    port = env_int("PORT", safe_int_value(server.get("port"), 9999), 1)
    workers = env_int("WORKERS", 1, 1)
    # Async single process is preferred on Termux; workers>1 is multi-process.
    kwargs = {
        "app": "app.main:app",
        "host": host,
        "port": port,
        "log_level": os.environ.get("LOG_LEVEL", "info"),
        "timeout_keep_alive": 75,
        "limit_concurrency": env_int(
            "LIMIT_CONCURRENCY",
            safe_int_value(
                (config.get("concurrency") or {}).get("server_limit_concurrency")
                or (safe_int_value((config.get("concurrency") or {}).get("max_upstream"), 64) + 32),
                96,
            ),
            1,
        ),
        "proxy_headers": True,
    }
    if workers > 1:
        kwargs["workers"] = workers
    print(f"AI API Switch PY starting on http://{host}:{port} workers={workers}", flush=True)
    uvicorn.run(**kwargs)


if __name__ == "__main__":
    main()
