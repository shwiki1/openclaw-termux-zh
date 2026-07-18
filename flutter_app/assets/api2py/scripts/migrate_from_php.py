#!/usr/bin/env python3
"""Copy config from PHP edition into this Python project."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from app.config import normalize_config  # noqa: E402

DEFAULT_SRC = ROOT.parent / "ai-api-switch-php" / "data" / "config.json"
TARGET = ROOT / "data" / "config.json"


def main() -> int:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
    if not src.exists():
        print(f"找不到配置: {src}", file=sys.stderr)
        return 1
    data = json.loads(src.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        print("源配置无效", file=sys.stderr)
        return 1
    data.setdefault("server", {})
    data["server"]["host"] = "127.0.0.1"
    data["server"]["port"] = 9999
    data = normalize_config(data)
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"配置已迁移到 {TARGET}")
    print("注意: PHP bcrypt 管理员密码哈希在本项目中不可直接验证，请重新初始化 admin_account。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
