#!/bin/bash
# ==================================================
# Claw Dashboard — 全自動安裝腳本 (Auto Setup Script)
#
# Supports: Linux (x86/ARM/Raspberry Pi) / macOS
#
# Usage:
#   Install:       bash setup.sh              (interactive)
#                  bash setup.sh --local       (local mode)
#                  bash setup.sh --lan         (LAN mode)
#   Update:        bash setup.sh --update
#   Uninstall:     bash setup.sh --uninstall
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
# UPDATE Command
# ============================================
do_update() {
  WORKSPACE="$HOME/.openclaw/workspace"
  PROJECT_DIR="$WORKSPACE/ClawDashboard"

  if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ ClawDashboard not found at ${PROJECT_DIR}"
    echo "   Run setup.sh without --update to install first."
    exit 1
  fi

  echo ""
  echo "🔄 Claw Dashboard — Update"
  echo "=================================================="

  cd "$PROJECT_DIR"

  echo "📥 Pulling latest code..."
  git pull || { echo "❌ git pull failed!"; exit 1; }

  echo "📦 Updating dependencies..."
  (cd backend && npm install --silent 2>&1) || { echo "❌ Backend install failed!"; exit 1; }
  (cd frontend && npm install --silent 2>&1) || { echo "❌ Frontend install failed!"; exit 1; }

  echo "🔄 Restarting services..."
  if command -v pm2 &>/dev/null; then
    pm2 restart claw-backend claw-frontend 2>/dev/null || {
      echo "⚠️  PM2 restart failed. Try: ./start.sh --bg"
    }
  else
    echo "⚠️  PM2 not found. Restart manually: ./start.sh --bg"
  fi

  echo ""
  echo "✅ Update complete!"
  echo "   pm2 status — check services"
  echo "   pm2 logs   — check for errors"
  echo "=================================================="
}

# ============================================
# UNINSTALL Command
# ============================================
do_uninstall() {
  WORKSPACE="$HOME/.openclaw/workspace"
  PROJECT_DIR="$WORKSPACE/ClawDashboard"

  echo ""
  echo "🗑️  Claw Dashboard — Uninstall"
  echo "=================================================="

  # Stop PM2 services
  if command -v pm2 &>/dev/null; then
    echo "🛑 Stopping services..."
    pm2 stop claw-backend claw-frontend 2>/dev/null || true
    pm2 delete claw-backend claw-frontend 2>/dev/null || true
    pm2 save 2>/dev/null || true
    echo "   ✅ PM2 services removed"
  fi

  # Warn about database
  if [ -f "$PROJECT_DIR/backend/bot.db" ]; then
    echo ""
    echo "   ⚠️  Database found: ${PROJECT_DIR}/backend/bot.db"
    echo "   This contains your tasks, logs, and agent states."
    if [ -t 0 ]; then
      read -r -p "   Backup database before deleting? [Y/n]: " backup_choice
      case "$backup_choice" in
        n|N|no|NO) ;;
        *)
          BACKUP_PATH="$HOME/claw-dashboard-backup-$(date +%Y%m%d%H%M%S).db"
          cp "$PROJECT_DIR/backend/bot.db" "$BACKUP_PATH"
          echo "   ✅ Database backed up to: ${BACKUP_PATH}"
          ;;
      esac
    fi
  fi

  # Remove project
  if [ -d "$PROJECT_DIR" ]; then
    if [ -t 0 ]; then
      read -r -p "Delete project files at ${PROJECT_DIR}? [y/N]: " confirm
    else
      confirm="y"
    fi

    case "$confirm" in
      y|Y|yes|YES)
        rm -rf "$PROJECT_DIR"
        echo "   ✅ Project files deleted"
        ;;
      *)
        echo "   ⏭️  Project files kept at ${PROJECT_DIR}"
        ;;
    esac
  fi

  echo ""
  echo "✅ Uninstall complete!"
  echo ""
  echo "   Note: PM2 itself was NOT removed."
  echo "   To remove PM2: npm uninstall -g pm2"
  echo "   To remove boot startup: pm2 unstartup"
  echo "=================================================="
}

# ============================================
# STATUS Command
# ============================================
do_status() {
  WORKSPACE="$HOME/.openclaw/workspace"
  PROJECT_DIR="$WORKSPACE/ClawDashboard"

  echo ""
  echo "📋 Claw Dashboard — Status"
  echo "=================================================="

  if [ ! -d "$PROJECT_DIR" ]; then
    echo "   ❌ Not installed (expected at ${PROJECT_DIR})"
    echo "=================================================="
    exit 1
  fi
  echo "   📁 Project: ${PROJECT_DIR}"

  # Read .env
  local host="127.0.0.1"
  if [ -f "$PROJECT_DIR/backend/.env" ]; then
    host=$(grep -E '^HOST=' "$PROJECT_DIR/backend/.env" 2>/dev/null | cut -d'=' -f2 | tr -d ' "'"'" || echo "127.0.0.1")
  fi

  if [ "$host" = "0.0.0.0" ]; then
    local lan_ip
    lan_ip=$(detect_lan_ip | tr -d '[:space:]')
    echo "   📡 Mode: LAN (${lan_ip:-unknown})"
    echo "   🌐 Dashboard: http://${lan_ip:-localhost}:5173"
    echo "   🔌 API:       http://${lan_ip:-localhost}:3001"
  else
    echo "   📡 Mode: Local"
    echo "   🌐 Dashboard: http://localhost:5173"
    echo "   🔌 API:       http://localhost:3001"
  fi

  # PM2 status
  if command -v pm2 &>/dev/null; then
    echo ""
    pm2 status 2>/dev/null | grep -E 'claw-|name' || echo "   PM2: no claw services found"
  else
    echo "   PM2: not installed"
  fi

  # Database size
  if [ -f "$PROJECT_DIR/backend/bot.db" ]; then
    local db_size
    db_size=$(du -h "$PROJECT_DIR/backend/bot.db" 2>/dev/null | awk '{print $1}')
    echo ""
    echo "   💾 Database: ${db_size} (${PROJECT_DIR}/backend/bot.db)"
  fi

  echo "=================================================="
}

# ============================================
# SWITCH MODE Command
# ============================================
do_switch() {
  local target_mode=$1
  WORKSPACE="$HOME/.openclaw/workspace"
  PROJECT_DIR="$WORKSPACE/ClawDashboard"

  if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Not installed. Run setup.sh first."
    exit 1
  fi

  cd "$PROJECT_DIR"

  echo ""
  echo "🔀 Switching to ${target_mode} mode..."

  if [ "$target_mode" = "lan" ]; then
    case "$OS" in
      macos) sed -i '' 's/^HOST=127.0.0.1/HOST=0.0.0.0/' backend/.env ;;
      *)     sed -i 's/^HOST=127.0.0.1/HOST=0.0.0.0/' backend/.env ;;
    esac
  else
    case "$OS" in
      macos) sed -i '' 's/^HOST=0.0.0.0/HOST=127.0.0.1/' backend/.env ;;
      *)     sed -i 's/^HOST=0.0.0.0/HOST=127.0.0.1/' backend/.env ;;
    esac
  fi

  # Restart if PM2 is running
  if command -v pm2 &>/dev/null && pm2 list 2>/dev/null | grep -q 'claw-'; then
    echo "🔄 Restarting services..."
    pm2 stop claw-backend claw-frontend 2>/dev/null || true
    pm2 delete claw-backend claw-frontend 2>/dev/null || true

    local vite_host="127.0.0.1"
    [ "$target_mode" = "lan" ] && vite_host="0.0.0.0"
    export VITE_HOST="$vite_host"
    export VITE_PORT="5173"
    pm2 start pm2.ecosystem.config.js
    pm2 save 2>/dev/null || true
  fi

  echo ""
  echo "✅ Switched to ${target_mode} mode!"
  if [ "$target_mode" = "lan" ]; then
    local lan_ip
    lan_ip=$(detect_lan_ip | tr -d '[:space:]')
    echo "   🌐 Dashboard: http://${lan_ip:-localhost}:5173"
  else
    echo "   🌐 Dashboard: http://localhost:5173"
  fi
  echo "=================================================="
}

# ============================================
# HELP
# ============================================
show_help() {
  echo "Usage: bash setup.sh [OPTION]"
  echo ""
  echo "Install:"
  echo "  (none)          Interactive (asks local/LAN)"
  echo "  --local         Local mode (localhost only)"
  echo "  --lan           LAN mode (network accessible)"
  echo ""
  echo "Manage:"
  echo "  --update        Pull latest code & restart"
  echo "  --status        Show service status & URLs"
  echo "  --switch-local  Switch to local mode"
  echo "  --switch-lan    Switch to LAN mode"
  echo "  --uninstall     Stop services & remove project"
  echo "  --help          Show this help"
}

# ============================================
# MAIN
# ============================================
detect_os

# Route commands
case "${1:-}" in
  --update)       do_update; exit 0 ;;
  --status)       do_status; exit 0 ;;
  --switch-local) do_switch local; exit 0 ;;
  --switch-lan)   do_switch lan; exit 0 ;;
  --uninstall)    do_uninstall; exit 0 ;;
  --help|-h)      show_help; exit 0 ;;
esac

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
