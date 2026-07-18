import base64
import json
import hashlib
import hmac
import os
import re
import secrets
import time
from typing import Any
from urllib.parse import urlparse

from starlette.requests import Request

from .config import load_config
from .paths import SESSION_DIR

USERNAME_RE = re.compile(r"^[A-Za-z0-9_.-]{3,32}$")
SESSION_ID_RE = re.compile(r"^[A-Za-z0-9_-]{20,128}$")
SESSION_COOKIE = "ai_api_switch_admin"
SESSION_TTL = 7 * 24 * 3600


def ensure_session_dir() -> None:
    SESSION_DIR.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(SESSION_DIR, 0o700)
    except OSError:
        pass


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _unb64(data: str) -> bytes:
    pad = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(data + pad)


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.scrypt(password.encode("utf-8"), salt=salt, n=2**14, r=8, p=1, dklen=32)
    return "scrypt$" + _b64(salt) + "$" + _b64(digest)


def verify_password(password: str, password_hash: str) -> bool:
    if not password_hash:
        return False
    # PHP password_hash bcrypt leftovers are not re-verified here; re-setup or reset needed.
    if password_hash.startswith("$2y$") or password_hash.startswith("$2a$") or password_hash.startswith("$2b$"):
        return False
    if not password_hash.startswith("scrypt$"):
        return False
    try:
        _, salt_b64, dig_b64 = password_hash.split("$", 2)
        salt = _unb64(salt_b64)
        expected = _unb64(dig_b64)
        actual = hashlib.scrypt(password.encode("utf-8"), salt=salt, n=2**14, r=8, p=1, dklen=len(expected))
        return hmac.compare_digest(actual, expected)
    except Exception:
        return False


def has_admin_account(config: dict[str, Any]) -> bool:
    account = config.get("admin_account") or {}
    return bool(account.get("username") and account.get("password_hash"))


def _session_path(sid: str) -> Any:
    if not SESSION_ID_RE.match(str(sid or "")):
        raise ValueError("invalid session id")
    return SESSION_DIR / f"{sid}.json"


def create_session(username: str) -> str:
    ensure_session_dir()
    sid = secrets.token_urlsafe(32)
    payload = {"username": username, "created": int(time.time())}
    path = _session_path(sid)
    path.write_text(json.dumps(payload), encoding="utf-8")
    try:
        os.chmod(path, 0o600)
    except OSError:
        pass
    return sid


def destroy_session(sid: str | None) -> None:
    if not sid:
        return
    try:
        path = _session_path(sid)
    except ValueError:
        return
    if path.exists():
        try:
            path.unlink()
        except OSError:
            pass


def read_session(sid: str | None) -> dict[str, Any] | None:
    if not sid:
        return None
    try:
        path = _session_path(sid)
    except ValueError:
        return None
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        created = int(data.get("created") or 0)
    except Exception:
        return None
    if created and time.time() - created > SESSION_TTL:
        destroy_session(sid)
        return None
    if not data.get("username"):
        return None
    return data


def is_local_request(request: Request) -> bool:
    client = request.client.host if request.client else ""
    return client in {"127.0.0.1", "::1"}


def bearer_token(request: Request) -> str:
    auth = request.headers.get("authorization") or ""
    if auth.lower().startswith("bearer "):
        return auth[7:].strip()
    return ""


def token_matches(token: str, tokens: list[str]) -> bool:
    if not token:
        return False
    for candidate in tokens:
        if not isinstance(candidate, str) or not candidate:
            continue
        if len(candidate) != len(token):
            continue
        if hmac.compare_digest(candidate, token):
            return True
    return False


def is_admin_session(request: Request, config: dict[str, Any]) -> bool:
    if not has_admin_account(config):
        return False
    sid = request.cookies.get(SESSION_COOKIE)
    session = read_session(sid)
    if not session:
        return False
    username = (config.get("admin_account") or {}).get("username") or ""
    return bool(username) and hmac.compare_digest(username, session.get("username") or "")


def account_input(body: dict[str, Any]) -> tuple[str, str]:
    username = str(body.get("username") or "").strip()
    password = str(body.get("password") or "")
    if not USERNAME_RE.match(username):
        raise ValueError("用户名需为 3 至 32 位字母、数字、点、下划线或连字符")
    if len(password) < 8 or len(password) > 256:
        raise ValueError("密码长度需为 8 至 256 位")
    return username, password


def require_same_origin(request: Request) -> None:
    source = request.headers.get("origin") or request.headers.get("referer") or ""
    if not source:
        raise PermissionError("管理写请求缺少 Origin 或 Referer")
    try:
        source_parts = urlparse(source)
        source_host = (source_parts.hostname or "").lower()
        source_scheme = (source_parts.scheme or "http").lower()
        source_port = source_parts.port or (443 if source_scheme == "https" else 80)
    except ValueError:
        raise PermissionError("管理写请求来源不匹配")
    host_header = request.headers.get("host") or ""
    # Preserve original host:port; scheme only for default port inference.
    forwarded_proto = (request.headers.get("x-forwarded-proto") or "").split(",")[0].strip().lower()
    request_scheme = forwarded_proto or source_scheme or "http"
    try:
        host_parts = urlparse("http://" + host_header)
        request_host = (host_parts.hostname or "").lower()
        request_port = host_parts.port or (443 if request_scheme == "https" else 80)
    except ValueError:
        raise PermissionError("管理写请求来源不匹配")
    if not source_host or source_host != request_host or int(source_port) != int(request_port):
        raise PermissionError("管理写请求来源不匹配")


async def require_api_auth(request: Request, config: dict[str, Any] | None = None) -> None:
    config = config or await load_config()
    if is_local_request(request):
        return
    if is_admin_session(request, config):
        return
    if is_local_request(request) and config.get("allow_local_unauthenticated"):
        return
    tokens = config.get("auth_tokens") or []
    if not tokens:
        return
    if not token_matches(bearer_token(request), tokens):
        raise PermissionError("无效的 API Key")


async def require_admin_auth(request: Request, config: dict[str, Any] | None = None) -> None:
    config = config or await load_config()
    if is_local_request(request):
        return
    if is_admin_session(request, config):
        if request.method not in {"GET", "HEAD", "OPTIONS"}:
            require_same_origin(request)
        return
    if is_local_request(request) and config.get("allow_local_unauthenticated"):
        return
    tokens = config.get("admin_tokens") or config.get("auth_tokens") or []
    if not tokens:
        raise PermissionError("未配置管理 Token")
    if not token_matches(bearer_token(request), tokens):
        raise PermissionError("无效的管理 Token")



def cleanup_sessions(max_keep: int = 200) -> int:
    ensure_session_dir()
    removed = 0
    files = sorted(SESSION_DIR.glob("*.json"), key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    now = time.time()
    keep = []
    for path in files:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            created = int(data.get("created") or 0)
            if created and now - created > SESSION_TTL:
                path.unlink(missing_ok=True)
                removed += 1
                continue
            keep.append(path)
        except Exception:
            try:
                path.unlink(missing_ok=True)
                removed += 1
            except OSError:
                pass
    for path in keep[max_keep:]:
        try:
            path.unlink(missing_ok=True)
            removed += 1
        except OSError:
            pass
    return removed



def password_hash_kind(password_hash: str) -> str:
    if not password_hash:
        return "empty"
    if password_hash.startswith("scrypt$"):
        return "scrypt"
    if password_hash.startswith("$2y$") or password_hash.startswith("$2a$") or password_hash.startswith("$2b$"):
        return "bcrypt"
    return "unknown"
