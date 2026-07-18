import asyncio
import time
from typing import Any

import httpx

from .config import load_config


class UpstreamClient:
    def __init__(self) -> None:
        self._client: httpx.AsyncClient | None = None
        self._semaphore: asyncio.Semaphore | None = None
        self._lock = asyncio.Lock()
        self._max_upstream = 64
        self._inflight = 0
        self._inflight_high_water = 0
        self._total_requests = 0
        self._total_errors = 0
        self._started_at = time.time()

    @property
    def stats(self) -> dict[str, Any]:
        return {
            "inflight": self._inflight,
            "inflight_high_water": self._inflight_high_water,
            "max_upstream": self._max_upstream,
            "total_requests": self._total_requests,
            "total_errors": self._total_errors,
            "uptime_sec": int(time.time() - self._started_at),
        }

    async def start(self) -> None:
        async with self._lock:
            if self._client is not None:
                return
            config = await load_config(mutable=False)
            concurrency = config.get("concurrency") or {}
            self._max_upstream = int(concurrency.get("max_upstream") or 64)
            limits = httpx.Limits(
                max_connections=int(concurrency.get("http_max_connections") or 100),
                max_keepalive_connections=int(concurrency.get("http_max_keepalive") or 40),
            )
            timeout = httpx.Timeout(
                connect=float(concurrency.get("connect_timeout") or 10.0),
                read=float(concurrency.get("read_timeout") or 300.0),
                write=float(concurrency.get("read_timeout") or 300.0),
                pool=float(concurrency.get("connect_timeout") or 10.0),
            )
            self._client = httpx.AsyncClient(
                limits=limits,
                timeout=timeout,
                follow_redirects=True,
                http2=False,
            )
            self._semaphore = asyncio.Semaphore(self._max_upstream)

    async def stop(self) -> None:
        async with self._lock:
            if self._client is not None:
                await self._client.aclose()
                self._client = None
            self._semaphore = None

    @property
    def client(self) -> httpx.AsyncClient:
        if self._client is None:
            raise RuntimeError("Upstream client not started")
        return self._client

    def _mark_start(self) -> None:
        self._inflight += 1
        self._total_requests += 1
        self._inflight_high_water = max(self._inflight_high_water, self._inflight)

    def _mark_end(self, error: bool = False) -> None:
        self._inflight = max(0, self._inflight - 1)
        if error:
            self._total_errors += 1

    async def request(self, method: str, url: str, **kwargs: Any) -> httpx.Response:
        if self._semaphore is None:
            await self.start()
        assert self._semaphore is not None
        async with self._semaphore:
            self._mark_start()
            errored = False
            try:
                return await self.client.request(method, url, **kwargs)
            except Exception:
                errored = True
                raise
            finally:
                self._mark_end(error=errored)

    async def stream(self, method: str, url: str, **kwargs: Any):
        if self._semaphore is None:
            await self.start()
        assert self._semaphore is not None

        class _Guard:
            def __init__(self, outer: "UpstreamClient", method: str, url: str, kwargs: dict[str, Any]):
                self.outer = outer
                self.method = method
                self.url = url
                self.kwargs = kwargs
                self.cm = None
                self.acquired = False
                self.started = False
                self.errored = False

            async def __aenter__(self):
                assert self.outer._semaphore is not None
                await self.outer._semaphore.acquire()
                self.acquired = True
                self.outer._mark_start()
                self.started = True
                try:
                    self.cm = self.outer.client.stream(self.method, self.url, **self.kwargs)
                    return await self.cm.__aenter__()
                except Exception:
                    self.errored = True
                    self._release()
                    raise

            async def __aexit__(self, exc_type, exc, tb):
                try:
                    if self.cm is not None:
                        return await self.cm.__aexit__(exc_type, exc, tb)
                finally:
                    if exc_type is not None:
                        self.errored = True
                    self._release()

            def _release(self):
                if self.started:
                    self.outer._mark_end(error=self.errored)
                    self.started = False
                if self.acquired and self.outer._semaphore is not None:
                    self.outer._semaphore.release()
                    self.acquired = False

        return _Guard(self, method, url, kwargs)


upstream = UpstreamClient()
