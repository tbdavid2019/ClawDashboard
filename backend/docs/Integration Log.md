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

-   呼叫 /api/agents
-   若為空不顯示 Team Status
-   busy/standby 依 activeAgent + status

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

# 六、PM2 常駐

## Backend

npm i -g pm2\
pm2 start server.js --name clawdashboard-backend

## Frontend

pm2 start "npm run dev -- --host" --name clawdashboard-frontend

------------------------------------------------------------------------

# 結論

完整閉環： Agent → Status → Task → Docs → UI
