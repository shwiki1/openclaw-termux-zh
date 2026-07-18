#!/data/data/com.termux/files/usr/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$DIR/server.pid"
PORT="${PORT:-9999}"
PID=""

is_current_server_pid() {
  local candidate="$1" cwd cmdline
  cwd="$(readlink "/proc/$candidate/cwd" 2>/dev/null || true)"
  [ "$cwd" = "$DIR" ] || return 1
  cmdline="$(tr '\0' ' ' < "/proc/$candidate/cmdline" 2>/dev/null || true)"
  case "$cmdline" in
    *python*server.py*) return 0 ;;
  esac
  return 1
}

find_server_pid() {
  local pid
  for proc in /proc/[0-9]*; do
    pid="${proc##*/}"
    if is_current_server_pid "$pid"; then
      echo "$pid"
      return 0
    fi
  done
  return 1
}

if [ -f "$PID_FILE" ]; then
  CANDIDATE="$(cat "$PID_FILE")"
  if case "$CANDIDATE" in ''|*[!0-9]*) false;; *) true;; esac && kill -0 "$CANDIDATE" 2>/dev/null && is_current_server_pid "$CANDIDATE"; then
    PID="$CANDIDATE"
  fi
fi
if [ -z "$PID" ]; then
  PID="$(find_server_pid || true)"
fi
if [ -z "$PID" ]; then
  rm -f "$PID_FILE"
  if curl -s --max-time 2 "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
    echo "端口 $PORT 上的服务正在运行，但当前环境无法识别其 PID" >&2
    exit 1
  fi
  echo "Python 服务未运行"
  exit 0
fi
kill "$PID"
for _ in 1 2 3 4 5; do
  kill -0 "$PID" 2>/dev/null || break
  sleep 1
done
if kill -0 "$PID" 2>/dev/null; then
  echo "Python 服务未能在 5 秒内停止 (PID $PID)" >&2
  exit 1
fi
rm -f "$PID_FILE"
echo "Python 服务已停止"
