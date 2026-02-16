#!/bin/bash
# ==================================================
# Claw Dashboard — 啟動腳本
#
# Usage:
#   ./start.sh            前景啟動 (dev mode, Ctrl+C 停止)
#   ./start.sh --bg       背景啟動 (PM2 daemon)
#   ./start.sh --stop     停止 PM2 服務
#   ./start.sh --status   查看 PM2 狀態
#   ./start.sh --boot     設定開機自啟 (PM2 startup)
# ==================================================

set -e
cd "$(dirname "$0")"

# ---- Helper: 讀取 backend/.env 的 HOST 設定 ----
get_host() {
  if [ -f "backend/.env" ]; then
    grep -E "^HOST=" backend/.env 2>/dev/null | cut -d'=' -f2 | tr -d ' "'"'" || echo "127.0.0.1"
  else
    echo "127.0.0.1"
  fi
}

# ---- Helper: 安裝依賴 ----
install_deps() {
  if [ ! -d "backend/node_modules" ]; then
    echo "📦 安裝 Backend 依賴..."
    (cd backend && npm install)
  fi
  if [ ! -d "frontend/node_modules" ]; then
    echo "📦 安裝 Frontend 依賴..."
    (cd frontend && npm install)
  fi
}

# ---- Helper: 確保 .env 存在 ----
ensure_env() {
  if [ ! -f "backend/.env" ]; then
    cp backend/.env.example backend/.env
    echo "📝 已建立 backend/.env (預設: 本地模式)"
    echo "   修改 HOST=0.0.0.0 可開放區網存取"
  fi
}

# ---- Helper: 偵測 LAN IP ----
get_lan_ip() {
  # Linux
  if command -v hostname &>/dev/null && hostname -I &>/dev/null 2>&1; then
    hostname -I 2>/dev/null | awk '{print $1}'
    return
  fi
  # macOS
  if command -v ipconfig &>/dev/null; then
    ipconfig getifaddr en0 2>/dev/null || echo "localhost"
    return
  fi
  echo "localhost"
}

# ---- Helper: 顯示存取資訊 ----
show_access_info() {
  local host
  host=$(get_host)
  if [ "$host" = "0.0.0.0" ]; then
    local lan_ip
    lan_ip=$(get_lan_ip)
    echo ""
    echo "   🌐 本地: http://localhost:5173"
    echo "   🌐 區網: http://${lan_ip}:5173"
    echo "   🔌 API:  http://${lan_ip}:3001"
  else
    echo ""
    echo "   🌐 Dashboard: http://localhost:5173"
    echo "   🔌 API:       http://localhost:3001"
    echo ""
    echo "   💡 需要區網存取？修改 backend/.env → HOST=0.0.0.0"
  fi
}

# ==================================================
# 模式: 前景啟動 (預設)
# ==================================================
start_foreground() {
  echo ""
  echo "🚀 Claw Dashboard 啟動中 (前景模式)..."
  echo "=================================================="

  install_deps
  ensure_env

  local host
  host=$(get_host)
  local vite_host="127.0.0.1"
  [ "$host" = "0.0.0.0" ] && vite_host="0.0.0.0"

  # 啟動 Backend
  echo "⚡ 啟動 Backend..."
  (cd backend && node server.js) &
  BACKEND_PID=$!
  sleep 1

  # 啟動 Frontend
  echo "⚡ 啟動 Frontend..."
  (cd frontend && npx vite --host "$vite_host") &
  FRONTEND_PID=$!

  echo ""
  echo "✅ Dashboard 啟動完成！"
  show_access_info
  echo ""
  echo "   按 Ctrl+C 停止所有服務"
  echo "=================================================="

  cleanup() {
    echo ""
    echo "🛑 停止服務..."
    kill $BACKEND_PID $FRONTEND_PID 2>/dev/null
    wait $BACKEND_PID $FRONTEND_PID 2>/dev/null
    echo "👋 已停止"
    exit 0
  }
  trap cleanup INT TERM
  wait
}

# ==================================================
# 模式: PM2 背景啟動
# ==================================================
start_background() {
  echo ""
  echo "🚀 Claw Dashboard 啟動中 (PM2 背景模式)..."
  echo "=================================================="

  # 檢查 PM2
  if ! command -v pm2 &>/dev/null; then
    echo "❌ 找不到 PM2，正在安裝..."
    npm install -g pm2
  fi

  install_deps
  ensure_env

  pm2 start pm2.ecosystem.config.js
  echo ""
  echo "✅ Dashboard 已在背景運行！"
  show_access_info
  echo ""
  echo "   📋 查看狀態: ./start.sh --status"
  echo "   📋 查看日誌: pm2 logs"
  echo "   🛑 停止服務: ./start.sh --stop"
  echo "   🔄 重啟服務: pm2 restart all"
  echo "=================================================="
}

# ==================================================
# 模式: 停止 PM2 服務
# ==================================================
stop_services() {
  if ! command -v pm2 &>/dev/null; then
    echo "❌ PM2 未安裝"
    exit 1
  fi
  pm2 stop claw-backend claw-frontend 2>/dev/null
  pm2 delete claw-backend claw-frontend 2>/dev/null
  echo "🛑 已停止所有 Claw Dashboard 服務"
}

# ==================================================
# 模式: 查看狀態
# ==================================================
show_status() {
  if ! command -v pm2 &>/dev/null; then
    echo "❌ PM2 未安裝"
    exit 1
  fi
  pm2 status
}

# ==================================================
# 模式: 設定開機自啟
# ==================================================
setup_boot() {
  if ! command -v pm2 &>/dev/null; then
    echo "❌ 找不到 PM2，正在安裝..."
    npm install -g pm2
  fi

  echo "🔧 設定開機自啟..."
  pm2 startup
  echo ""
  echo "⚠️  請先用 ./start.sh --bg 啟動服務，然後執行:"
  echo "    pm2 save"
  echo ""
  echo "   這樣重開機後 PM2 會自動恢復服務"
}

# ==================================================
# Main
# ==================================================
case "${1:-}" in
  --bg|--background)
    start_background
    ;;
  --stop)
    stop_services
    ;;
  --status)
    show_status
    ;;
  --boot|--startup)
    setup_boot
    ;;
  --help|-h)
    echo "Usage: ./start.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  (no args)    前景啟動 (dev mode, Ctrl+C 停止)"
    echo "  --bg         背景啟動 (PM2 daemon)"
    echo "  --stop       停止 PM2 服務"
    echo "  --status     查看 PM2 狀態"
    echo "  --boot       設定開機自啟"
    echo "  --help       顯示此說明"
    ;;
  *)
    start_foreground
    ;;
esac
