#!/bin/bash
# ==================================================
# Claw Dashboard — 全自動安裝腳本
#
# 這個腳本由 OpenClaw Agent 或使用者手動執行，
# 會自動完成所有安裝、配置、啟動步驟。
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/tbdavid2019/ClawDashboard/main/setup.sh | bash
#   或
#   bash setup.sh
# ==================================================

set -e

echo ""
echo "🦞 Claw Dashboard — 全自動安裝"
echo "=================================================="

# ---- 1. 定位工作目錄 ----
WORKSPACE="$HOME/.openclaw/workspace"
PROJECT_DIR="$WORKSPACE/ClawDashboard"

mkdir -p "$WORKSPACE"

# ---- 2. Clone 或更新 ----
if [ -d "$PROJECT_DIR" ]; then
  echo "📂 專案已存在，執行 git pull..."
  cd "$PROJECT_DIR"
  git pull
else
  echo "📥 Clone 專案..."
  cd "$WORKSPACE"
  git clone https://github.com/tbdavid2019/ClawDashboard.git
  cd "$PROJECT_DIR"
fi

# ---- 3. 安裝依賴 ----
echo "📦 安裝 Backend 依賴..."
(cd backend && npm install --silent)

echo "📦 安裝 Frontend 依賴..."
(cd frontend && npm install --silent)

# ---- 4. 偵測網路模式並配置 .env ----
# 自動偵測：如果有多張網卡或非 127.0.0.1 的 IP，預設用區網模式
detect_lan_ip() {
  # Linux
  if command -v hostname &>/dev/null; then
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -n "$ip" ] && [ "$ip" != "127.0.0.1" ]; then
      echo "$ip"
      return
    fi
  fi
  # macOS
  if command -v ipconfig &>/dev/null; then
    local ip
    ip=$(ipconfig getifaddr en0 2>/dev/null)
    if [ -n "$ip" ]; then
      echo "$ip"
      return
    fi
  fi
  echo ""
}

LAN_IP=$(detect_lan_ip)

if [ ! -f "backend/.env" ]; then
  cp backend/.env.example backend/.env
fi

if [ -n "$LAN_IP" ]; then
  # 有區網 IP → 開啟區網模式
  sed -i.bak 's/^HOST=127.0.0.1/HOST=0.0.0.0/' backend/.env 2>/dev/null || \
  sed -i '' 's/^HOST=127.0.0.1/HOST=0.0.0.0/' backend/.env
  rm -f backend/.env.bak
  ACCESS_URL="http://${LAN_IP}:5173"
  API_URL="http://${LAN_IP}:3001"
  echo "🌐 偵測到區網 IP: ${LAN_IP} → 自動啟用區網模式"
else
  ACCESS_URL="http://localhost:5173"
  API_URL="http://localhost:3001"
  echo "🏠 未偵測到區網 IP → 使用本地模式"
fi

# ---- 5. 安裝 PM2 (如果沒有) ----
if ! command -v pm2 &>/dev/null; then
  echo "📦 安裝 PM2..."
  npm install -g pm2
fi

# ---- 6. 啟動服務 (PM2 背景) ----
echo "🚀 啟動服務 (PM2 背景模式)..."

# 先停止舊服務 (如果有)
pm2 stop claw-backend claw-frontend 2>/dev/null || true
pm2 delete claw-backend claw-frontend 2>/dev/null || true

pm2 start pm2.ecosystem.config.js

# ---- 7. 設定開機自啟 ----
echo "🔧 設定開機自啟..."
pm2 startup 2>/dev/null || true
pm2 save 2>/dev/null || true

# ---- 8. 等待服務就緒 ----
echo "⏳ 等待服務就緒..."
sleep 3

# 驗證 Backend
if curl -s "${API_URL}/" >/dev/null 2>&1; then
  echo "✅ Backend 就緒"
else
  echo "⚠️  Backend 可能還在啟動中，請稍後再試"
fi

# ---- 9. 輸出結果 ----
echo ""
echo "=================================================="
echo "🎉 Claw Dashboard 安裝完成！"
echo ""
echo "   🌐 Dashboard: ${ACCESS_URL}"
echo "   🔌 API:       ${API_URL}"
echo ""
echo "   📋 管理指令:"
echo "      pm2 status         查看狀態"
echo "      pm2 logs           即時日誌"
echo "      pm2 restart all    重啟服務"
echo ""
echo "   📁 專案位置: ${PROJECT_DIR}"
echo "=================================================="
echo ""
echo "📌 下一步：請讓 Agent 讀取以下文件以建立長期記憶："
echo "   ${PROJECT_DIR}/backend/docs/Integration Log.md"
echo "   ${PROJECT_DIR}/backend/docs/Long Memory Prompts.md"
