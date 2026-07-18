from pathlib import Path

APP_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = APP_ROOT / "data"
CONFIG_FILE = DATA_DIR / "config.json"
DB_FILE = DATA_DIR / "stats.db"
STATIC_DIR = APP_ROOT / "public" / "static"
SESSION_DIR = DATA_DIR / "sessions"
