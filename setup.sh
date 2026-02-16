#!/bin/bash
# ==================================================
# Claw Dashboard — 全自動安裝腳本 (Auto Setup Script)
#
# Supports: Linux (x86/ARM/Raspberry Pi) / macOS
#
# Usage:
#   Interactive:   bash setup.sh
#   Local mode:    bash setup.sh --local
#   LAN mode:      bash setup.sh --lan
#   Remote (curl): bash <(curl -sSL https://raw.githubusercontent.com/tbdavid2019/ClawDashboard/main/setup.sh) --lan
# ==================================================

set -e

BACKEND_PORT=3001
FRONTEND_PORT=5173

# ============================================
# OS Detection
# ============================================
detect_os() {
  case "$(uname -s)" in
    Linux*)
      OS="linux"
      case "$(uname -m)" in
        armv7l|armv6l) ARCH="arm32 (Raspberry Pi)" ;;
        aarch64)       ARCH="arm64 (Raspberry Pi / ARM)" ;;
        x86_64)        ARCH="x86_64" ;;
        *)             ARCH="$(uname -m)" ;;
      esac
      ;;
    Darwin*)
      OS="macos"
      case "$(uname -m)" in
        arm64) ARCH="Apple Silicon (M1/M2/M3)" ;;
        *)     ARCH="Intel" ;;
      esac
      ;;
    *)
      OS="unknown"
      ARCH="$(uname -m)"
      ;;
  esac
}

# ============================================
# LAN IP Detection
# ============================================
detect_lan_ip() {
  case "$OS" in
    linux)
      hostname -I 2>/dev/null | awk '{print $1}' || true
      ;;
    macos)
      ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true
      ;;
  esac
}

# ============================================
# Network Mode Selection
# ============================================
select_network_mode() {
  # Check CLI args first
  case "${1:-}" in
    --local|--localhost)
      NET_MODE="local"
      return
      ;;
    --lan|--network|--remote)
      NET_MODE="lan"
      return
      ;;
  esac

  # Interactive mode — ask user
  local lan_ip
  lan_ip=$(detect_lan_ip | tr -d '[:space:]')

  echo ""
  echo "🌐 Network Mode / 網路模式"
  echo "─────────────────────────────────────────"
  echo "  1) Local only  — localhost only (safe, default)"
  echo "                    只有本機可存取 (預設)"
  echo ""
  echo "  2) LAN access  — accessible from other machines"
  echo "                    區網內其他電腦可存取"
  if [ -n "$lan_ip" ] && [ "$lan_ip" != "127.0.0.1" ]; then
    echo "                    (detected IP: ${lan_ip})"
  fi
  echo "─────────────────────────────────────────"
  echo ""

  # If stdin is a terminal, ask interactively
  if [ -t 0 ]; then
    read -r -p "Choose [1/2] (default: 1): " choice
  else
    # Non-interactive (piped) — default to local
    echo "   (non-interactive, defaulting to local mode)"
    choice="1"
  fi

  case "$choice" in
    2|lan|LAN) NET_MODE="lan" ;;
    *)         NET_MODE="local" ;;
  esac
}

# ============================================
# Port Conflict Resolution
# ============================================
kill_port() {
  local port=$1
  local pids=""

  case "$OS" in
    linux)
      pids=$(ss -tlnp 2>/dev/null | grep ":${port} " | grep -oP 'pid=\K[0-9]+' 2>/dev/null | sort -u || true)
      if [ -z "$pids" ] && command -v lsof &>/dev/null; then
        pids=$(lsof -ti:${port} 2>/dev/null || true)
      fi
      ;;
    macos)
      if command -v lsof &>/dev/null; then
        pids=$(lsof -ti:${port} 2>/dev/null || true)
      fi
      ;;
  esac

  if [ -n "$pids" ]; then
    echo "   ⚠️  Port ${port} in use (PID: $(echo $pids | tr '\n' ' ')), killing..."
    for pid in $pids; do
      kill "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null || true
    done
    sleep 1
    echo "   ✅ Port ${port} freed"
  else
    echo "   ✅ Port ${port} available"
  fi
}

# ============================================
# Health Check
# ============================================
check_health() {
  local url=$1
  local name=$2
  local max_retries=15
  local retry=0

  while [ $retry -lt $max_retries ]; do
    if curl -s --connect-timeout 2 "${url}" >/dev/null 2>&1; then
      echo "   ✅ ${name} ready"
      return 0
    fi
    retry=$((retry + 1))
    sleep 2
  done

  echo "   ❌ ${name} not responding!"
  return 1
}

# ============================================
# MAIN
# ============================================
detect_os

echo ""
echo "🦞 Claw Dashboard — Auto Setup"
echo "=================================================="
echo "   OS:   ${OS} / ${ARCH}"
echo "=================================================="

# ---- Environment Check ----
echo ""
echo "🔍 Checking environment..."

if ! command -v node &>/dev/null; then
  echo "❌ Node.js not found!"
  case "$OS" in
    linux)
      echo "   Install:"
      echo "   curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
      echo "   sudo apt-get install -y nodejs"
      ;;
    macos)
      echo "   Install: brew install node"
      ;;
  esac
  exit 1
fi

NODE_VER=$(node -v)
NODE_MAJOR=$(echo "$NODE_VER" | sed 's/v//' | cut -d. -f1)
if [ "$NODE_MAJOR" -lt 18 ]; then
  echo "❌ Node.js ${NODE_VER} too old (need >= 18)"
  exit 1
fi
echo "   ✅ Node.js ${NODE_VER}"
echo "   ✅ npm $(npm -v)"

if ! command -v git &>/dev/null; then
  echo "❌ git not found!"
  case "$OS" in
    linux)  echo "   Install: sudo apt-get install -y git" ;;
    macos)  echo "   Install: xcode-select --install" ;;
  esac
  exit 1
fi
echo "   ✅ git"

# ---- Network Mode ----
select_network_mode "$1"
echo ""
echo "   📡 Mode: ${NET_MODE}"

# ---- Clone or Update ----
WORKSPACE="$HOME/.openclaw/workspace"
PROJECT_DIR="$WORKSPACE/ClawDashboard"
mkdir -p "$WORKSPACE"

echo ""
if [ -d "$PROJECT_DIR" ]; then
  echo "📂 Project exists, pulling updates..."
  cd "$PROJECT_DIR"
  git pull
else
  echo "📥 Cloning..."
  cd "$WORKSPACE"
  git clone https://github.com/tbdavid2019/ClawDashboard.git
  cd "$PROJECT_DIR"
fi

# ---- Install Dependencies ----
echo ""
echo "📦 Installing dependencies..."
(cd backend && npm install --silent 2>&1) || { echo "❌ Backend install failed!"; exit 1; }
echo "   ✅ Backend"
(cd frontend && npm install --silent 2>&1) || { echo "❌ Frontend install failed!"; exit 1; }
echo "   ✅ Frontend"

# ---- Port Check ----
echo ""
echo "🔍 Checking ports..."
if command -v pm2 &>/dev/null; then
  pm2 stop claw-backend claw-frontend 2>/dev/null || true
  pm2 delete claw-backend claw-frontend 2>/dev/null || true
fi
kill_port $BACKEND_PORT
kill_port $FRONTEND_PORT

# ---- Configure .env ----
echo ""
echo "⚙️  Configuring..."

if [ ! -f "backend/.env" ]; then
  cp backend/.env.example backend/.env
fi

LAN_IP=$(detect_lan_ip | tr -d '[:space:]')

if [ "$NET_MODE" = "lan" ]; then
  case "$OS" in
    macos) sed -i '' 's/^HOST=127.0.0.1/HOST=0.0.0.0/' backend/.env ;;
    *)     sed -i 's/^HOST=127.0.0.1/HOST=0.0.0.0/' backend/.env ;;
  esac
  VITE_HOST="0.0.0.0"
  if [ -n "$LAN_IP" ] && [ "$LAN_IP" != "127.0.0.1" ]; then
    ACCESS_URL="http://${LAN_IP}:${FRONTEND_PORT}"
    API_URL="http://${LAN_IP}:${BACKEND_PORT}"
  else
    ACCESS_URL="http://localhost:${FRONTEND_PORT}"
    API_URL="http://localhost:${BACKEND_PORT}"
    echo "   ⚠️  LAN mode set but no LAN IP detected"
  fi
else
  # Ensure local mode
  case "$OS" in
    macos) sed -i '' 's/^HOST=0.0.0.0/HOST=127.0.0.1/' backend/.env ;;
    *)     sed -i 's/^HOST=0.0.0.0/HOST=127.0.0.1/' backend/.env ;;
  esac
  VITE_HOST="127.0.0.1"
  ACCESS_URL="http://localhost:${FRONTEND_PORT}"
  API_URL="http://localhost:${BACKEND_PORT}"
fi
echo "   ✅ .env configured (${NET_MODE} mode)"

# ---- Install PM2 & Start ----
echo ""
if ! command -v pm2 &>/dev/null; then
  echo "📦 Installing PM2..."
  npm install -g pm2 2>/dev/null || sudo npm install -g pm2
fi

echo "🚀 Starting services..."
export VITE_HOST="${VITE_HOST}"
export VITE_PORT="${FRONTEND_PORT}"

pm2 start pm2.ecosystem.config.js || {
  echo "❌ PM2 start failed! Check: pm2 logs"
  exit 1
}

# ---- Boot Persistence ----
echo ""
echo "🔧 Boot persistence..."
STARTUP_CMD=$(pm2 startup 2>&1 | grep "sudo" | head -1 || true)
if [ -n "$STARTUP_CMD" ]; then
  echo "   ⚠️  Run this to enable boot startup:"
  echo "   ${STARTUP_CMD}"
fi
pm2 save 2>/dev/null || true
echo "   ✅ PM2 state saved"

# ---- Firewall (Linux) ----
if [ "$OS" = "linux" ] && [ "$NET_MODE" = "lan" ]; then
  echo ""
  echo "🔥 Firewall check..."
  if command -v ufw &>/dev/null; then
    UFW_STATUS=$(sudo ufw status 2>/dev/null | head -1 || echo "")
    if echo "$UFW_STATUS" | grep -qi "active"; then
      echo "   ⚠️  ufw is active! Run:"
      echo "      sudo ufw allow ${BACKEND_PORT}"
      echo "      sudo ufw allow ${FRONTEND_PORT}"
    fi
  elif command -v firewall-cmd &>/dev/null; then
    echo "   ⚠️  firewalld detected. Run:"
    echo "      sudo firewall-cmd --add-port=${BACKEND_PORT}/tcp --permanent"
    echo "      sudo firewall-cmd --add-port=${FRONTEND_PORT}/tcp --permanent"
    echo "      sudo firewall-cmd --reload"
  fi
fi

# ---- Health Check ----
echo ""
echo "⏳ Health check..."
BACKEND_OK=true
FRONTEND_OK=true
check_health "${API_URL}/" "Backend" || BACKEND_OK=false
check_health "${ACCESS_URL}/" "Frontend" || FRONTEND_OK=false

# ---- Result ----
echo ""
echo "=================================================="
if [ "$BACKEND_OK" = true ] && [ "$FRONTEND_OK" = true ]; then
  echo "🎉 Installation Complete!"
else
  echo "⚠️  Installed with issues:"
  [ "$BACKEND_OK" = false ] && echo "   ❌ Backend — pm2 logs claw-backend"
  [ "$FRONTEND_OK" = false ] && echo "   ❌ Frontend — pm2 logs claw-frontend"
  echo ""
  echo "   Common fixes:"
  echo "   • Port conflict  → lsof -i:${BACKEND_PORT} ; lsof -i:${FRONTEND_PORT}"
  echo "   • Missing deps   → cd backend && npm install"
  echo "   • Old Node.js    → node -v (need >= 18)"
  [ "$OS" = "linux" ] && echo "   • Firewall        → sudo ufw allow ${BACKEND_PORT} && sudo ufw allow ${FRONTEND_PORT}"
fi

echo ""
echo "   🌐 Dashboard: ${ACCESS_URL}"
echo "   🔌 API:       ${API_URL}"
echo "   📡 Mode:      ${NET_MODE}"
echo "   �️  System:   ${OS} / ${ARCH}"
echo ""
echo "   📋 Commands:"
echo "      pm2 status       — check status"
echo "      pm2 logs         — view logs"
echo "      pm2 restart all  — restart"
echo "      ./start.sh --stop — stop all"
echo ""
echo "   📁 Project: ${PROJECT_DIR}"
echo "=================================================="
echo ""
echo "📌 Next: Have your AI agent read the docs:"
echo "   ${PROJECT_DIR}/backend/docs/"
