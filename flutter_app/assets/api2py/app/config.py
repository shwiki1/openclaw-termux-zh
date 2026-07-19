import asyncio
import json
import os
import re
import time
from copy import deepcopy
from typing import Any

from .paths import CONFIG_FILE, DATA_DIR

DEFAULT_CONFIG: dict[str, Any] = {
    "server": {"host": "127.0.0.1", "port": 9999},
    "providers": {},
    "model_mappings": {},
    "prefix_routes": {},
    "default_provider": "",
    "force_default_provider": False,
    "auth_tokens": [],
    "admin_tokens": [],
    "pricing": {},
    "log_max": 500,
    "debug_requests": False,
    "allow_local_unauthenticated": False,
    "admin_account": {},
    "concurrency": {
        "max_upstream": 64,
        "http_max_connections": 100,
        "http_max_keepalive": 40,
        "connect_timeout": 10.0,
        "read_timeout": 300.0,
        "write_queue_size": 1000,
        "max_body_bytes": 8_000_000,
        "server_limit_concurrency": 96,
    },
}

DEFAULT_PRICING: dict[str, dict[str, Any]] = {
    # Per 1M tokens. Only keep verified API prices here; do not add zero-price
    # placeholders or unverified latest-model guesses.
    "deepseek-v4-flash": {"provider": "DeepSeek", "currency": "USD", "input": 0.14, "output": 0.28, "source": "api-docs.deepseek.com/quick_start/pricing cache miss", "updated": "2026-07-18"},
    "deepseek-v4-pro": {"provider": "DeepSeek", "currency": "USD", "input": 0.435, "output": 0.87, "source": "api-docs.deepseek.com/quick_start/pricing cache miss", "updated": "2026-07-18"},
    "deepseek-reasoner": {"provider": "DeepSeek", "currency": "USD", "input": 0.14, "output": 0.28, "source": "DeepSeek compatibility alias for v4-flash until deprecation", "updated": "2026-07-18"},
    "kimi-k3": {"provider": "Kimi", "currency": "CNY", "input": 20.0, "output": 100.0, "source": "platform.kimi.com/docs/pricing/chat-k3.md cache miss", "updated": "2026-07-18"},
    "kimi-k2.7-code": {"provider": "Kimi", "currency": "CNY", "input": 6.5, "output": 27.0, "source": "platform.kimi.com/docs/pricing/chat-k27-code.md cache miss", "updated": "2026-07-18"},
    "kimi-k2.6": {"provider": "Kimi", "currency": "CNY", "input": 6.5, "output": 27.0, "source": "platform.kimi.com/docs/pricing/chat-k26.md cache miss", "updated": "2026-07-18"},
    "qwen3.7-max": {"provider": "Qwen", "currency": "CNY", "input": 12.0, "output": 36.0, "source": "help.aliyun.com/zh/model-studio/model-pricing original price", "updated": "2026-07-18"},
    "qwen3.7-plus": {"provider": "Qwen", "currency": "CNY", "input": 2.0, "output": 8.0, "source": "help.aliyun.com/zh/model-studio/model-pricing base tier original price", "updated": "2026-07-18"},
    "qwen3.6-flash": {"provider": "Qwen", "currency": "CNY", "input": 1.2, "output": 7.2, "source": "help.aliyun.com/zh/model-studio/model-pricing base tier original price", "updated": "2026-07-18"},
    "gpt-5.6-sol": {"provider": "OpenAI", "currency": "USD", "input": 5.0, "output": 30.0, "source": "user supplied price", "updated": "2026-07-18"},
    "gpt-5.6-terra": {"provider": "OpenAI", "currency": "USD", "input": 2.5, "output": 15.0, "source": "user supplied price", "updated": "2026-07-18"},
    "gpt-5.6-luna": {"provider": "OpenAI", "currency": "USD", "input": 1.0, "output": 6.0, "source": "user supplied price", "updated": "2026-07-18"},
    "gpt-5.5": {"provider": "OpenAI", "currency": "USD", "input": 5.0, "output": 30.0, "source": "user supplied price", "updated": "2026-07-18"},
    "gpt-5.4-pro": {"provider": "OpenAI", "currency": "USD", "input": 30.0, "output": 180.0, "source": "user supplied price", "updated": "2026-07-18"},
    "gpt-5.4": {"provider": "OpenAI", "currency": "USD", "input": 2.5, "output": 15.0, "source": "user supplied price", "updated": "2026-07-18"},
    "claude-fable-5": {"provider": "Anthropic", "currency": "USD", "input": 10.0, "output": 50.0, "source": "user supplied price", "updated": "2026-07-18"},
    "claude-opus-4.8": {"provider": "Anthropic", "currency": "USD", "input": 5.0, "output": 25.0, "source": "user supplied price", "updated": "2026-07-18"},
    "claude-sonnet-5": {"provider": "Anthropic", "currency": "USD", "input": 3.0, "output": 15.0, "source": "user supplied price", "updated": "2026-07-18"},
    "claude-opus-4.7": {"provider": "Anthropic", "currency": "USD", "input": 5.0, "output": 25.0, "source": "user supplied price", "updated": "2026-07-18"},
    "claude-opus-4.6": {"provider": "Anthropic", "currency": "USD", "input": 5.0, "output": 25.0, "source": "user supplied price", "updated": "2026-07-18"},
    "claude-sonnet-4.6": {"provider": "Anthropic", "currency": "USD", "input": 3.0, "output": 15.0, "source": "user supplied price", "updated": "2026-07-18"},
    "gemini-3.5-flash": {"provider": "Google", "currency": "USD", "input": 1.5, "output": 9.0, "source": "user supplied price", "updated": "2026-07-18"},
    "gemini-3.1-pro": {"provider": "Google", "currency": "USD", "input": 4.0, "output": 18.0, "source": "user supplied price", "updated": "2026-07-18"},
    "gemini-2.5-flash": {"provider": "Google", "currency": "USD", "input": 0.3, "output": 2.5, "source": "user supplied price", "updated": "2026-07-18"},
    "grok-4.5": {"provider": "xAI", "currency": "USD", "input": 2.0, "output": 6.0, "source": "user supplied price", "updated": "2026-07-18"},
    "grok-4.3": {"provider": "xAI", "currency": "USD", "input": 1.25, "output": 2.5, "source": "user supplied price", "updated": "2026-07-18"},
    "grok-4.20": {"provider": "xAI", "currency": "USD", "input": 1.25, "output": 2.5, "source": "user supplied price", "updated": "2026-07-18"},
    "glm-5.2": {"provider": "Zhipu GLM", "currency": "USD", "input": 1.0, "output": 3.0, "source": "user supplied approximate price; input midpoint of 0.95-1.05", "updated": "2026-07-18"},
    "glm-5.1": {"provider": "Zhipu GLM", "currency": "USD", "input": 1.4, "output": 4.4, "source": "user supplied official price", "updated": "2026-07-18"},
    "glm-5": {"provider": "Zhipu GLM", "currency": "USD", "input": 1.0, "output": 3.2, "source": "user supplied official price", "updated": "2026-07-18"},
    "mimo-v2.5-pro": {"provider": "Xiaomi MiMo", "currency": "CNY", "input": 3.0, "output": 6.0, "cache": 0.025, "source": "user supplied price", "updated": "2026-07-18"},
    "mimo-v2.5": {"provider": "Xiaomi MiMo", "currency": "CNY", "input": 1.0, "output": 2.0, "cache": 0.02, "source": "user supplied price", "updated": "2026-07-18"},
}

_VALID_PROTOCOLS = {"openai", "responses", "anthropic", "ollama"}
_PROVIDER_ID_RE = re.compile(r"^[A-Za-z0-9_.-]{1,64}$")

_lock = asyncio.Lock()
_cache: dict[str, Any] | None = None
_cache_mtime: float | None = None


def ensure_data_dir() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(DATA_DIR, 0o700)
    except OSError:
        pass


def default_config() -> dict[str, Any]:
    cfg = deepcopy(DEFAULT_CONFIG)
    cfg["pricing"] = deepcopy(DEFAULT_PRICING)
    return cfg


def is_valid_protocol(protocol: str) -> bool:
    return protocol in _VALID_PROTOCOLS


def safe_int(value: Any, default: int, minimum: int | None = None, maximum: int | None = None) -> int:
    try:
        result = int(value)
    except (TypeError, ValueError):
        result = int(default)
    if minimum is not None:
        result = max(minimum, result)
    if maximum is not None:
        result = min(maximum, result)
    return result


def safe_float(value: Any, default: float, minimum: float | None = None, maximum: float | None = None) -> float:
    try:
        result = float(value)
    except (TypeError, ValueError):
        result = float(default)
    if minimum is not None:
        result = max(minimum, result)
    if maximum is not None:
        result = min(maximum, result)
    return result


def normalize_protocol(protocol: str | None, provider: dict | None = None) -> str:
    protocol = (protocol or "").strip().lower()
    if protocol in {"chat", "chat_completions"}:
        protocol = "openai"
    if protocol in {"response", "codex"}:
        protocol = "responses"
    if not protocol or not is_valid_protocol(protocol):
        protocol = ((provider or {}).get("type") or "openai").strip().lower()
    return protocol if is_valid_protocol(protocol) else "openai"


def client_protocol(protocol: str) -> str:
    return "openai" if protocol == "ollama" else protocol


def endpoint_for_protocol(protocol: str) -> str:
    protocol = client_protocol(protocol)
    if protocol == "responses":
        return "/v1/responses"
    if protocol == "anthropic":
        return "/v1/messages"
    return "/v1/chat/completions"


def normalize_config(config: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(config, dict):
        raise ValueError("配置必须是 JSON 对象")
    for key, value in DEFAULT_CONFIG.items():
        if key not in config:
            config[key] = deepcopy(value)
    for field in (
        "providers",
        "model_mappings",
        "prefix_routes",
        "auth_tokens",
        "admin_tokens",
        "pricing",
        "admin_account",
        "concurrency",
    ):
        if not isinstance(config.get(field), dict) and field not in {
            "auth_tokens",
            "admin_tokens",
        }:
            if field in {"auth_tokens", "admin_tokens"}:
                pass
            else:
                raise ValueError(f"{field} 必须是对象或数组")
    if not isinstance(config.get("auth_tokens"), list):
        raise ValueError("auth_tokens 必须是数组")
    if not isinstance(config.get("admin_tokens"), list):
        raise ValueError("admin_tokens 必须是数组")
    if not isinstance(config.get("server"), dict):
        raise ValueError("server 必须是对象")
    if not isinstance(config.get("concurrency"), dict):
        config["concurrency"] = deepcopy(DEFAULT_CONFIG["concurrency"])
    else:
        for k, v in DEFAULT_CONFIG["concurrency"].items():
            config["concurrency"].setdefault(k, v)
    for pid, provider in list(config["providers"].items()):
        if not _PROVIDER_ID_RE.match(str(pid)):
            raise ValueError(f"提供商 ID {pid} 格式无效")
        if not isinstance(provider, dict):
            raise ValueError(f"提供商 {pid} 必须是对象")
        base_url = str(provider.get("base_url") or "").strip()
        if not base_url or not (base_url.startswith("http://") or base_url.startswith("https://")):
            raise ValueError(f"提供商 {pid} 的 Base URL 无效")
        ptype = str(provider.get("type") or "openai").strip().lower()
        if not is_valid_protocol(ptype):
            raise ValueError(f"提供商 {pid} 使用了未知类型 {ptype}")
        config["providers"][pid]["type"] = ptype
        config["providers"][pid]["enabled"] = bool(provider.get("enabled"))

    for alias, mapping in list(config["model_mappings"].items()):
        if not isinstance(mapping, dict) or not mapping.get("provider") or not mapping.get("model"):
            raise ValueError(f"模型映射 {alias} 缺少提供商或实际模型名")
        protocol = str(mapping.get("protocol") or "openai").strip().lower()
        if not is_valid_protocol(protocol) or protocol == "ollama":
            raise ValueError(f"模型映射 {alias} 使用了无效的对外协议 {protocol}")
        config["model_mappings"][alias]["protocol"] = protocol

    pricing = config.get("pricing") or {}
    if not isinstance(pricing, dict):
        pricing = {}
    merged_pricing = deepcopy(DEFAULT_PRICING)
    merged_pricing.update(pricing)
    for model, price in list(merged_pricing.items()):
        if not isinstance(price, dict):
            merged_pricing.pop(model, None)
            continue
        price["input"] = safe_float(price.get("input"), 0.0, 0.0, 1_000_000.0)
        price["output"] = safe_float(price.get("output"), 0.0, 0.0, 1_000_000.0)
        currency = str(price.get("currency") or "USD").strip().upper()
        price["currency"] = currency[:8] if currency else "USD"
        if "provider" in price:
            price["provider"] = str(price.get("provider") or "")[:64]
        if "source" in price:
            price["source"] = str(price.get("source") or "")[:200]
        if "updated" in price:
            price["updated"] = str(price.get("updated") or "")[:32]
        if "needs_review" in price:
            price["needs_review"] = bool(price.get("needs_review"))
    config["pricing"] = merged_pricing

    config["log_max"] = safe_int(config.get("log_max"), 500, 0, 100000)
    concurrency = config["concurrency"]
    concurrency["max_upstream"] = safe_int(concurrency.get("max_upstream"), 64, 1, 10000)
    concurrency["http_max_connections"] = safe_int(concurrency.get("http_max_connections"), 100, 1, 20000)
    concurrency["http_max_keepalive"] = safe_int(concurrency.get("http_max_keepalive"), 40, 0, 20000)
    concurrency["connect_timeout"] = safe_float(concurrency.get("connect_timeout"), 10.0, 0.1, 300.0)
    concurrency["read_timeout"] = safe_float(concurrency.get("read_timeout"), 300.0, 1.0, 3600.0)
    concurrency["write_queue_size"] = safe_int(concurrency.get("write_queue_size"), 1000, 100, 1000000)
    concurrency["max_body_bytes"] = safe_int(concurrency.get("max_body_bytes"), 8_000_000, 1024, 512_000_000)
    concurrency["server_limit_concurrency"] = safe_int(
        concurrency.get("server_limit_concurrency"),
        max(96, concurrency["max_upstream"] + 32),
        1,
        50000,
    )
    config["force_default_provider"] = bool(config.get("force_default_provider"))
    config["debug_requests"] = bool(config.get("debug_requests"))
    config["allow_local_unauthenticated"] = bool(config.get("allow_local_unauthenticated"))
    return config


def _read_config_sync() -> dict[str, Any]:
    ensure_data_dir()
    if not CONFIG_FILE.exists():
        cfg = default_config()
        _write_config_sync(cfg)
        return cfg
    raw = CONFIG_FILE.read_text(encoding="utf-8")
    config = json.loads(raw)
    if not isinstance(config, dict):
        config = default_config()
    for key, value in DEFAULT_CONFIG.items():
        if key not in config:
            config[key] = deepcopy(value)
    # nested concurrency defaults
    if not isinstance(config.get("concurrency"), dict):
        config["concurrency"] = deepcopy(DEFAULT_CONFIG["concurrency"])
    else:
        for k, v in DEFAULT_CONFIG["concurrency"].items():
            config["concurrency"].setdefault(k, v)
    if not isinstance(config.get("server"), dict):
        config["server"] = deepcopy(DEFAULT_CONFIG["server"])
    else:
        for k, v in DEFAULT_CONFIG["server"].items():
            config["server"].setdefault(k, v)
    return normalize_config(config)


def _write_config_sync(config: dict[str, Any]) -> dict[str, Any]:
    ensure_data_dir()
    config = normalize_config(deepcopy(config))
    tmp = CONFIG_FILE.with_suffix(f".{os.getpid()}.tmp")
    payload = json.dumps(config, ensure_ascii=False, indent=2)
    tmp.write_text(payload, encoding="utf-8")
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    os.replace(tmp, CONFIG_FILE)
    try:
        os.chmod(CONFIG_FILE, 0o600)
    except OSError:
        pass
    return config


async def load_config(force: bool = False, *, mutable: bool = True) -> dict[str, Any]:
    """Load config.

    mutable=True  returns a deep copy safe for in-place admin edits.
    mutable=False returns the shared cached object for read-only hot paths.
    Callers using mutable=False must not mutate the returned dict.
    """
    global _cache, _cache_mtime

    async with _lock:
        mtime = CONFIG_FILE.stat().st_mtime if CONFIG_FILE.exists() else None
        if not force and _cache is not None and mtime == _cache_mtime:
            cached = _cache
        else:
            cached = None

    if cached is None:
        # Disk IO outside the lock so concurrent readers are not blocked.
        config = await asyncio.to_thread(_read_config_sync)
        async with _lock:
            # Another coroutine may have refreshed the cache while we loaded.
            mtime = CONFIG_FILE.stat().st_mtime if CONFIG_FILE.exists() else time.time()
            if (
                not force
                and _cache is not None
                and _cache_mtime is not None
                and mtime == _cache_mtime
            ):
                cached = _cache
            else:
                _cache = config
                _cache_mtime = mtime
                cached = _cache

    if not mutable:
        return cached
    # Deep copy off the event loop to reduce event-loop stalls under load.
    return await asyncio.to_thread(deepcopy, cached)


async def save_config(config: dict[str, Any]) -> dict[str, Any]:
    global _cache, _cache_mtime
    async with _lock:
        # Serialize config writes so concurrent admin updates cannot interleave.
        saved = await asyncio.to_thread(_write_config_sync, config)
        _cache = saved
        _cache_mtime = CONFIG_FILE.stat().st_mtime if CONFIG_FILE.exists() else time.time()
        cached = _cache
    return await asyncio.to_thread(deepcopy, cached)


def mask_secret(value: str) -> str:
    if not value:
        return ""
    if len(value) <= 8:
        return "***"
    return value[:4] + ("*" * (len(value) - 8)) + value[-4:]


def redact_config(config: dict[str, Any]) -> dict[str, Any]:
    safe = deepcopy(config)
    safe.pop("admin_account", None)
    for pid, provider in safe.get("providers", {}).items():
        provider["api_key"] = mask_secret(str(provider.get("api_key") or ""))
    safe["auth_tokens"] = [str(token) for token in config.get("auth_tokens", [])]
    safe["admin_tokens"] = [mask_secret(str(token)) for token in config.get("admin_tokens", [])]
    return safe


def preserve_masked_secrets(incoming: dict[str, Any], existing: dict[str, Any]) -> dict[str, Any]:
    incoming = deepcopy(incoming)
    incoming["admin_account"] = deepcopy(existing.get("admin_account") or {})
    for pid, provider in list((incoming.get("providers") or {}).items()):
        key = str(provider.get("api_key") or "")
        if "*" in key and pid in (existing.get("providers") or {}):
            provider["api_key"] = existing["providers"][pid].get("api_key", "")
    for field in ("auth_tokens", "admin_tokens"):
        if field not in incoming:
            incoming[field] = deepcopy(existing.get(field) or [])
            continue
        tokens = incoming.get(field) or []
        if tokens and all("*" in str(token) for token in tokens):
            incoming[field] = deepcopy(existing.get(field) or [])
    return incoming


def config_warnings(config: dict[str, Any]) -> list[str]:
    warnings: list[str] = []
    for alias, mapping in (config.get("model_mappings") or {}).items():
        provider = mapping.get("provider")
        if provider not in (config.get("providers") or {}):
            warnings.append(f"模型映射 {alias} 引用了不存在的提供商 {provider}")
        protocol = mapping.get("protocol")
        if protocol and not is_valid_protocol(str(protocol)):
            warnings.append(f"模型映射 {alias} 使用了未知协议 {protocol}")
    return warnings


def resolve_route(config: dict[str, Any], model: str):
    route_protocol = ""
    providers = config.get("providers") or {}
    mappings = config.get("model_mappings") or {}
    if config.get("force_default_provider"):
        provider_id = config.get("default_provider") or ""
        actual_model = model
        mapping = mappings.get(model)
        if mapping:
            route_protocol = mapping.get("protocol") or ""
            if mapping.get("provider") == provider_id and mapping.get("model"):
                actual_model = mapping["model"]
    elif model in mappings:
        mapping = mappings[model]
        provider_id = mapping["provider"]
        actual_model = mapping["model"]
        route_protocol = mapping.get("protocol") or ""
    else:
        # prefix routes: longest prefix wins
        prefix_routes = config.get("prefix_routes") or {}
        best_prefix = ""
        provider_id = ""
        if isinstance(prefix_routes, dict):
            for prefix, pid in prefix_routes.items():
                p = str(prefix or "")
                if p and model.startswith(p) and len(p) > len(best_prefix):
                    best_prefix = p
                    provider_id = str(pid or "")
        if not provider_id:
            return None, None, None, None, f"模型别名 {model} 未配置"
        actual_model = model
        route_protocol = ""

    provider = providers.get(provider_id)
    if not provider or not provider.get("enabled"):
        return None, None, None, None, f"提供商 {provider_id} 未启用或不存在"
    return (
        provider_id,
        provider,
        actual_model,
        normalize_protocol(route_protocol, provider),
        None,
    )


async def get_config_snapshot() -> dict[str, Any]:
    """Return a read-only config snapshot for request hot paths."""
    return await load_config(mutable=False)
