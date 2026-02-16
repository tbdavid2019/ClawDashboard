#!/bin/bash
# ==================================================
# Claw Dashboard — 啟動/管理腳本
#
# Usage:
#   ./start.sh            前景啟動 (dev mode, Ctrl+C stop)
#   ./start.sh --bg       PM2 背景啟動
#   ./start.sh --stop     停止 PM2 服務
#   ./start.sh --status   查看 PM2 狀態
#   ./start.sh --boot     設定開機自啟
#   ./start.sh --help     顯示說明
# ==================================================

set -e
cd "$(dirname "$0")"

# ---- OS Detection ----
case "$(uname -s)" in
  Linux*)  OS="linux" ;;
  Darwin*) OS="macos" ;;
  *)       OS="unknown" ;;
esac

# ---- Read .env ----
get_env_val() {
  local key=$1
  local default=$2
  if [ -f "backend/.env" ]; then
    local val
    val=$(grep -E "^${key}=" backend/.env 2>/dev/null | cut -d'=' -f2 | tr -d ' "'"'" || true)
    echo "${val:-$default}"
  else
    echo "$default"
  fi
}

HOST=$(get_env_val "HOST" "127.0.0.1")
BACKEND_PORT=$(get_env_val "PORT" "3001")
FRONTEND_PORT=5173

# ---- LAN IP ----
get_lan_ip() {
  case "$OS" in
    linux)  hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost" ;;
    macos)  ipconfig getifaddr en0 2>/dev/null || echo "localhost" ;;
    *)      echo "localhost" ;;
  esac
}

# ---- Install Deps ----
install_deps() {
  if [ ! -d "backend/node_modules" ]; then
    echo "📦 Installing backend deps..."
    (cd backend && npm install)
  fi
  if [ ! -d "frontend/node_modules" ]; then
    echo "📦 Installing frontend deps..."
    (cd frontend && npm install)
  fi
}

# ---- Ensure .env ----
ensure_env() {
  if [ ! -f "backend/.env" ]; then
    cp backend/.env.example backend/.env
    echo "📝 Created backend/.env (default: local mode)"
    echo "   Set HOST=0.0.0.0 for LAN access"
  fi
}

# ---- Port Check ----
check_port() {
  local port=$1
  local pids=""
  case "$OS" in
    linux)
      pids=$(ss -tlnp 2>/dev/null | grep ":${port} " | grep -oP 'pid=\K[0-9]+' 2>/dev/null | sort -u || true)
      [ -z "$pids" ] && pids=$(lsof -ti:${port} 2>/dev/null || true)
      ;;
    macos)
      pids=$(lsof -ti:${port} 2>/dev/null || true)
      ;;
  esac
  if [ -n "$pids" ]; then
    echo "   ⚠️  Port ${port} in use (PID: $(echo $pids | tr '\n' ' ')), killing..."
    for pid in $pids; do
      kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
    done
    sleep 1
  fi
}

# ---- Show Access Info ----
show_info() {
  if [ "$HOST" = "0.0.0.0" ]; then
    local lan_ip
    lan_ip=$(get_lan_ip)
    echo "   🌐 Local:     http://localhost:${FRONTEND_PORT}"
    echo "   🌐 LAN:       http://${lan_ip}:${FRONTEND_PORT}"
    echo "   🔌 API:       http://${lan_ip}:${BACKEND_PORT}"
  else
    echo "   🌐 Dashboard: http://localhost:${FRONTEND_PORT}"
    echo "   🔌 API:       http://localhost:${BACKEND_PORT}"
    echo "   💡 LAN access? Set HOST=0.0.0.0 in backend/.env"
  fi
}

# ==================================================
# Foreground Mode
# ==================================================
start_foreground() {
  echo ""
  echo "🚀 Claw Dashboard (foreground mode)"
  echo "=================================================="
  install_deps
  ensure_env

  local vite_host="127.0.0.1"
  [ "$HOST" = "0.0.0.0" ] && vite_host="0.0.0.0"

  check_port $BACKEND_PORT
  check_port $FRONTEND_PORT

  echo "⚡ Starting backend..."
  (cd backend && node server.js) &
  BACKEND_PID=$!
  sleep 1

  echo "⚡ Starting frontend..."
  (cd frontend && VITE_HOST="$vite_host" VITE_PORT="$FRONTEND_PORT" npx vite) &
  FRONTEND_PID=$!

  echo ""
  echo "✅ Running!"
  show_info
  echo ""
  echo "   Press Ctrl+C to stop"
  echo "=================================================="

  cleanup() {
    echo ""
    echo "🛑 Stopping..."
    kill $BACKEND_PID $FRONTEND_PID 2>/dev/null
    wait $BACKEND_PID $FRONTEND_PID 2>/dev/null
    echo "👋 Stopped"
    exit 0
  }
  trap cleanup INT TERM
  wait
}

# ==================================================
# PM2 Background Mode
# ==================================================
start_background() {
  echo ""
  echo "🚀 Claw Dashboard (PM2 background mode)"
  echo "=================================================="
  install_deps
  ensure_env

  if ! command -v pm2 &>/dev/null; then
    echo "📦 Installing PM2..."
    npm install -g pm2 2>/dev/null || sudo npm install -g pm2
  fi

  check_port $BACKEND_PORT
  check_port $FRONTEND_PORT

  local vite_host="127.0.0.1"
  [ "$HOST" = "0.0.0.0" ] && vite_host="0.0.0.0"

  export VITE_HOST="$vite_host"
  export VITE_PORT="$FRONTEND_PORT"

  pm2 start pm2.ecosystem.config.js

  echo ""
  echo "✅ Running in background!"
  show_info
  echo ""
  echo "   pm2 status   — check status"
  echo "   pm2 logs     — view logs"
  echo "   ./start.sh --stop — stop"
  echo "=================================================="
}

# ==================================================
# Other Commands
# ==================================================
stop_services() {
  if ! command -v pm2 &>/dev/null; then echo "❌ PM2 not installed"; exit 1; fi
  pm2 stop claw-backend claw-frontend 2>/dev/null || true
  pm2 delete claw-backend claw-frontend 2>/dev/null || true
  echo "🛑 Stopped"
}

show_status() {
  if ! command -v pm2 &>/dev/null; then echo "❌ PM2 not installed"; exit 1; fi
  pm2 status
}

setup_boot() {
  if ! command -v pm2 &>/dev/null; then
    echo "📦 Installing PM2..."
    npm install -g pm2 2>/dev/null || sudo npm install -g pm2
  fi
  echo "🔧 Setting up boot startup..."
  pm2 startup
  echo ""
  echo "⚠️  After starting services with ./start.sh --bg, run: pm2 save"
}

show_help() {
  echo "Usage: ./start.sh [OPTION]"
  echo ""
  echo "Options:"
  echo "  (none)     Foreground mode (Ctrl+C to stop)"
  echo "  --bg       Background mode (PM2 daemon)"
  echo "  --stop     Stop PM2 services"
  echo "  --status   Show PM2 status"
  echo "  --boot     Setup boot startup"
  echo "  --help     Show this help"
}

# ==================================================
# Main
# ==================================================
case "${1:-}" in
  --bg|--background) start_background ;;
  --stop)            stop_services ;;
  --status)          show_status ;;
  --boot|--startup)  setup_boot ;;
  --help|-h)         show_help ;;
  *)                 start_foreground ;;
esac
