# ClawDashboard Integration Log

------------------------------------------------------------------------

# 一、系統架構總覽

## Status Flow（狀態燈）

### 前端

-   frontend/src/App.jsx
-   輪詢 GET /api/status
-   狀態：idle / thinking / acting

### 後端

-   SQLite table: status (state, active_agent)
-   SQLite table: agent_states (name, state, updated_at)
-   API:
    -   GET /api/status
    -   PUT /api/status (Global Status)
    -   POST /api/status/agent (Individual Agent Status)

------------------------------------------------------------------------

## Task Flow（看板）

### API

-   GET /api/tasks
-   POST /api/tasks
-   PUT /api/tasks/:id

### 任務狀態

-   todo
-   in_progress
-   done

------------------------------------------------------------------------

# 二、Docs 系統架構

## Workspace Root

path.join(\_\_dirname, '../../..', 'workspace')

### 類型分類

### Workspace

-   id = file:`<relative_path>`{=html}
-   category = System
-   唯讀

### Backend Docs

來源: backend/docs - category = Docs

------------------------------------------------------------------------

# 三、Agents Sidebar

## Backend

GET /api/agents\
來源: ../../.. /openclaw.json\
排除 defaults

## Frontend

-   呼叫 /api/agents (agent 列表)
-   呼叫 /api/status (含 agents map，各 agent 獨立狀態)
-   若為空不顯示 Team Status
-   優先以 agentStates[name] 判斷個別狀態
-   fallback: activeAgent + global status
-   三種顯示: busy (acting) / thinking / standby (idle)

------------------------------------------------------------------------

# 四、自動化規則

## 狀態規則

-   收到任務 → thinking
-   開始執行 → acting
-   完成 → idle

## Task 規則

-   每次對話建立 task
-   title = 第一行摘要（≤120字）
-   description = 全文
-   狀態流轉：todo → in_progress → done

------------------------------------------------------------------------

# 五、Webhook

POST /api/webhook/message

Payload: { "text": "...", "stage": "received \| started \| completed",
"taskId": "optional" }

行為: - received → 建立 todo - started → in_progress - completed → done

------------------------------------------------------------------------

# 六、部署配置

## 網路模式

-   backend/.env 中的 HOST 控制綁定地址
-   HOST=127.0.0.1 → 本地模式（預設，安全）
-   HOST=0.0.0.0 → 區網模式（LAN 可存取）
-   前端 config.js 會自動偵測 hostname，無需手動設定 API URL

## 啟動方式

-   ./start.sh → 前景啟動（開發用，Ctrl+C 停止）
-   ./start.sh --bg → PM2 背景常駐
-   ./start.sh --stop → 停止 PM2 服務
-   ./start.sh --status → 查看 PM2 狀態
-   ./start.sh --boot → 設定開機自啟（需搭配 pm2 save）

## PM2 Ecosystem

-   pm2.ecosystem.config.js 定義 claw-backend 與 claw-frontend
-   自動讀取 backend/.env 的 HOST 設定來決定 Vite 的 --host 參數

------------------------------------------------------------------------

# 結論

完整閉環： Agent → Status → Task → Docs → UI
