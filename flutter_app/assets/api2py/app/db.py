import asyncio
import json
import logging
import time
import uuid
from datetime import datetime, timezone
from typing import Any

import aiosqlite

from .config import ensure_data_dir
from .config import safe_int
from .paths import DB_FILE

logger = logging.getLogger("ai-api-switch.db")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


class Database:
    def __init__(self) -> None:
        self._conn: aiosqlite.Connection | None = None
        self._write_queue: asyncio.Queue | None = None
        self._writer_task: asyncio.Task | None = None
        self._lock = asyncio.Lock()
        self._ops_lock = asyncio.Lock()
        self._write_count = 0
        self._dropped_writes = 0
        self._last_trim_at = 0.0
        self._last_trim_count = 0
        self._queue_high_water = 0

    @property
    def stats(self) -> dict[str, Any]:
        qsize = self._write_queue.qsize() if self._write_queue is not None else 0
        return {
            "queue_size": qsize,
            "queue_high_water": self._queue_high_water,
            "write_count": self._write_count,
            "dropped_writes": self._dropped_writes,
            "last_trim_count": self._last_trim_count,
        }

    async def start(self, write_queue_size: int = 1000) -> None:
        ensure_data_dir()
        async with self._lock:
            if self._conn is not None:
                return
            self._conn = await aiosqlite.connect(DB_FILE)
            self._conn.row_factory = aiosqlite.Row
            await self._conn.execute("PRAGMA busy_timeout = 10000")
            await self._conn.execute("PRAGMA journal_mode = WAL")
            await self._conn.execute("PRAGMA synchronous = NORMAL")
            await self._conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS usage (
                    id TEXT PRIMARY KEY,
                    timestamp TEXT,
                    provider TEXT,
                    model TEXT,
                    input_tokens INTEGER,
                    output_tokens INTEGER,
                    total_tokens INTEGER,
                    cost_usd REAL,
                    latency_ms INTEGER,
                    status TEXT
                );
                CREATE TABLE IF NOT EXISTS request_log (
                    id TEXT PRIMARY KEY,
                    timestamp TEXT,
                    provider TEXT,
                    model_alias TEXT,
                    actual_model TEXT,
                    stream INTEGER,
                    status_code INTEGER,
                    latency_ms INTEGER,
                    req_body TEXT,
                    resp_body TEXT,
                    error TEXT
                );
                CREATE TABLE IF NOT EXISTS response_state (
                    id TEXT PRIMARY KEY,
                    timestamp TEXT,
                    messages TEXT
                );
                """
            )
            await self._conn.commit()
            self._write_queue = asyncio.Queue(maxsize=max(100, write_queue_size))
            self._writer_task = asyncio.create_task(self._writer_loop(), name="db-writer")

    async def stop(self) -> None:
        # Non-blocking shutdown signal: avoid hanging forever if the queue is full.
        if self._write_queue is not None:
            try:
                self._write_queue.put_nowait(None)
            except asyncio.QueueFull:
                try:
                    # Drop one pending write and re-signal shutdown.
                    _ = self._write_queue.get_nowait()
                    self._write_queue.task_done()
                except Exception:
                    pass
                try:
                    self._write_queue.put_nowait(None)
                except Exception:
                    # Last resort: cancel writer and continue closing.
                    if self._writer_task is not None:
                        self._writer_task.cancel()
        if self._writer_task is not None:
            try:
                await asyncio.wait_for(self._writer_task, timeout=2.0)
            except Exception:
                try:
                    self._writer_task.cancel()
                except Exception:
                    pass
            self._writer_task = None
        if self._conn is not None:
            try:
                await self._conn.close()
            except Exception:
                pass
            self._conn = None
        self._write_queue = None

    async def _writer_loop(self) -> None:
        assert self._write_queue is not None
        assert self._conn is not None
        while True:
            item = await self._write_queue.get()
            if item is None:
                self._write_queue.task_done()
                break
            batch = [item]
            # batch drain for better write throughput
            shutdown = False
            while len(batch) < 64:
                try:
                    nxt = self._write_queue.get_nowait()
                except asyncio.QueueEmpty:
                    break
                if nxt is None:
                    # Do not re-queue: if the queue is full, await put(None) deadlocks
                    # the single writer task. Handle shutdown after this batch.
                    shutdown = True
                    self._write_queue.task_done()
                    break
                batch.append(nxt)
            try:
                async with self._ops_lock:
                    for sql, params in batch:
                        await self._conn.execute(sql, params)
                        self._write_count += 1
                    await self._conn.commit()
            except Exception as exc:
                logger.warning("db writer batch failed: %s", exc)
            finally:
                for _ in batch:
                    self._write_queue.task_done()
            if shutdown:
                break

    async def execute(self, sql: str, params: tuple | list = ()) -> None:
        assert self._conn is not None
        async with self._ops_lock:
            await self._conn.execute(sql, params)
            await self._conn.commit()

    async def fetchone(self, sql: str, params: tuple | list = ()) -> dict[str, Any] | None:
        assert self._conn is not None
        async with self._ops_lock:
            async with self._conn.execute(sql, params) as cursor:
                row = await cursor.fetchone()
                return dict(row) if row else None

    async def fetchall(self, sql: str, params: tuple | list = ()) -> list[dict[str, Any]]:
        assert self._conn is not None
        async with self._ops_lock:
            async with self._conn.execute(sql, params) as cursor:
                rows = await cursor.fetchall()
                return [dict(row) for row in rows]

    async def enqueue(self, sql: str, params: tuple | list = ()) -> None:
        if self._write_queue is None:
            await self.execute(sql, params)
            return
        try:
            self._write_queue.put_nowait((sql, params))
            self._queue_high_water = max(self._queue_high_water, self._write_queue.qsize())
        except asyncio.QueueFull:
            try:
                await asyncio.wait_for(self._write_queue.put((sql, params)), timeout=0.05)
                self._queue_high_water = max(self._queue_high_water, self._write_queue.qsize())
            except Exception:
                self._dropped_writes += 1
                if self._dropped_writes % 50 == 1:
                    logger.warning("db write queue full, dropped=%s", self._dropped_writes)

    async def record_usage(
        self,
        config: dict[str, Any],
        provider: str,
        model: str,
        input_tokens: int,
        output_tokens: int,
        latency_ms: int,
        status: str,
    ) -> None:
        cost = usage_cost(config, model, input_tokens, output_tokens)
        await self.enqueue(
            "INSERT INTO usage VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                uuid.uuid4().hex,
                utc_now(),
                provider,
                model,
                int(input_tokens),
                int(output_tokens),
                int(input_tokens) + int(output_tokens),
                float(cost),
                int(latency_ms),
                status,
            ),
        )

    async def log_request(
        self,
        config: dict[str, Any],
        provider: str,
        alias: str,
        actual: str,
        stream: bool,
        status_code: int,
        latency_ms: int,
        request_body: str,
        response_body: str,
        error: str,
    ) -> None:
        await self.enqueue(
            "INSERT INTO request_log VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                uuid.uuid4().hex,
                utc_now(),
                provider,
                alias,
                actual,
                1 if stream else 0,
                int(status_code),
                int(latency_ms),
                request_log_payload(config, request_body),
                request_log_payload(config, response_body),
                request_log_error(config, error),
            ),
        )
        await self.maybe_trim_request_logs(config)

    async def maybe_trim_request_logs(self, config: dict[str, Any], force: bool = False) -> None:
        now = time.time()
        # trim at most every 5s unless forced
        if not force and (now - self._last_trim_at) < 5:
            return
        self._last_trim_at = now
        await self.trim_request_logs(config)

    async def trim_request_logs(self, config: dict[str, Any]) -> None:
        limit = safe_int(config.get("log_max"), 500, 0, 100000)
        if limit == 0:
            await self.enqueue("DELETE FROM request_log", ())
            self._last_trim_count = 0
            return
        await self.enqueue(
            "DELETE FROM request_log WHERE id NOT IN (SELECT id FROM request_log ORDER BY timestamp DESC LIMIT ?)",
            (limit,),
        )
        self._last_trim_count = limit

    async def load_response_state(self, response_id: str) -> list[dict[str, Any]] | None:
        if not response_id:
            return []
        row = await self.fetchone("SELECT messages FROM response_state WHERE id = ?", (response_id,))
        if not row or not row.get("messages"):
            return None
        try:
            messages = json.loads(row["messages"])
        except Exception:
            return None
        return messages if isinstance(messages, list) else None

    async def save_response_state(self, response_id: str, messages: list[dict[str, Any]]) -> None:
        if not response_id:
            return
        await self.enqueue(
            "INSERT OR REPLACE INTO response_state VALUES (?, ?, ?)",
            (response_id, utc_now(), json.dumps(messages, ensure_ascii=False)),
        )
        await self.enqueue(
            "DELETE FROM response_state WHERE id NOT IN (SELECT id FROM response_state ORDER BY timestamp DESC LIMIT 200)",
            (),
        )


def usage_tokens(usage: Any) -> tuple[int, int]:
    if not isinstance(usage, dict):
        return 0, 0
    input_tokens = usage.get("prompt_tokens", usage.get("input_tokens", 0)) or 0
    output_tokens = usage.get("completion_tokens", usage.get("output_tokens", 0)) or 0
    try:
        return int(input_tokens), int(output_tokens)
    except Exception:
        return 0, 0


def usage_cost(config: dict[str, Any], model: str, input_tokens: int, output_tokens: int) -> float:
    pricing = (config.get("pricing") or {}).get(model) or {}
    if not isinstance(pricing, dict):
        return 0.0
    if str(pricing.get("currency") or "USD").upper() != "USD":
        return 0.0
    try:
        input_rate = float(pricing.get("input") or 0)
        output_rate = float(pricing.get("output") or 0)
    except (TypeError, ValueError):
        return 0.0
    return ((input_tokens * input_rate) + (output_tokens * output_rate)) / 1_000_000.0


def pricing_summary(config: dict[str, Any], model: str) -> dict[str, Any]:
    pricing = (config.get("pricing") or {}).get(model) or {}
    if not isinstance(pricing, dict):
        return {"input": 0.0, "output": 0.0, "source": "", "updated": "", "needs_review": False}
    return {
        "provider": str(pricing.get("provider") or ""),
        "currency": str(pricing.get("currency") or "USD").upper(),
        "input": float(pricing.get("input") or 0),
        "output": float(pricing.get("output") or 0),
        "source": str(pricing.get("source") or ""),
        "updated": str(pricing.get("updated") or ""),
        "needs_review": bool(pricing.get("needs_review")),
    }


def request_log_payload(config: dict[str, Any], value: Any) -> str:
    if not config.get("debug_requests"):
        return ""
    return str(value or "")[:2000]


def request_log_error(config: dict[str, Any], value: Any) -> str:
    if not value:
        return ""
    if not config.get("debug_requests"):
        return "上游请求失败；启用 debug_requests 后可查看详细错误。"
    return str(value)[:2000]


db = Database()
