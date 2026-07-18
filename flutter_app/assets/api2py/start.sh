#!/data/data/com.termux/files/usr/bin/bash
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$DIR/server.pid"
LOG_FILE="$DIR/server.log"
PORT="${PORT:-9999}"
WORKERS="${WORKERS:-1}"
HOST="${HOST:-127.0.0.1}"

find_server_pid() {
  local pid cwd cmdline
  for proc in /proc/[0-9]*; do
    pid="${proc##*/}"
    cwd="$(readlink "$proc/cwd" 2>/dev/null || true)"
    [ "$cwd" = "$DIR" ] || continue
    cmdline="$(tr '\0' ' ' < "$proc/cmdline" 2>/dev/null || true)"
    case "$cmdline" in
      *python*server.py*) echo "$pid"; return 0 ;;
    esac
  done
  return 1
}

if curl -s --max-time 2 "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
  RUNNING_PID="$(find_server_pid || true)"
  if [ -n "$RUNNING_PID" ]; then
    echo "$RUNNING_PID" > "$PID_FILE"
    echo "Python 服务已在运行 (PID $RUNNING_PID, 端口 $PORT)"
    exit 0
  fi
  echo "端口 $PORT 已有服务响应，但不是当前目录的 server.py" >&2
  exit 1
fi

cd "$DIR"
rm -f "$PID_FILE"
rm -f "$LOG_FILE"
export HOST PORT WORKERS
if command -v setsid >/dev/null 2>&1; then
  setsid python3 "$DIR/server.py" </dev/null >> "$LOG_FILE" 2>&1 &
else
  nohup python3 "$DIR/server.py" </dev/null >> "$LOG_FILE" 2>&1 &
fi
PID=$!
echo "$PID" > "$PID_FILE"
sleep 2
if ! kill -0 "$PID" 2>/dev/null || ! curl -s --max-time 3 "http://127.0.0.1:$PORT/" >/dev/null; then
  kill "$PID" 2>/dev/null || true
  rm -f "$PID_FILE"
  echo "Python 服务启动失败，请查看 $LOG_FILE" >&2
  if [ -s "$LOG_FILE" ]; then
    echo "--- server.log 最近输出 ---" >&2
    tail -80 "$LOG_FILE" >&2 || true
  fi
  exit 1
fi
echo "Python 服务启动成功 (PID $PID, 端口 $PORT, Workers $WORKERS)"
