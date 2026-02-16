# ClawDashboard Integration Log

---

# 一、系統架構總覽

Dashboard 是**被動接收**架構。Agent 必須主動打 API 回報狀態。

## 資料流

```
Agent → POST API → Backend (Express) → SQLite + SSE → Frontend (React)
                                      → 讀取 openclaw.json (Agent 列表)
                                      → 掃描 WORKSPACE_ROOT/*.md (Docs)
```

---

## Status Flow（狀態燈）

### 後端

- SQLite table: `status` (state, active_agent, updated_at)
- SQLite table: `agent_states` (name, state, updated_at)
- API:
    - `GET /api/status` — 取得全域狀態 + 各 Agent 狀態 map
    - `PUT /api/status` — 更新全域狀態 (`state` + `activeAgent`)
    - `POST /api/status/agent` — 更新個別 Agent 狀態 (`name` + `state`)

### 前端

- 透過 SSE (`/api/events`) 即時接收狀態更新
- 三種狀態顯示: busy (acting) / thinking / standby (idle)

---

## Task Flow（看板）

### API

- `GET /api/tasks`
- `POST /api/tasks`
- `PUT /api/tasks/:id`

### 任務狀態

- `todo` → `in_progress` → `done`

---

## Webhook（自動化驅動）

`POST /api/webhook/message`

```json
{
  "text": "任務內容",
  "stage": "received | started | completed",
  "taskId": "optional (started/completed 必填)"
}
```

| stage | 結果 |
|:---|:---|
| `received` | 建立 todo task |
| `started` | task → in_progress |
| `completed` | task → done |

---

# 二、Docs 系統

## 兩種文件來源

| 來源 | 類別 | 權限 | 路徑 |
|:---|:---|:---|:---|
| Workspace | System | 唯讀 | `WORKSPACE_ROOT` 下所有 `.md`（遞迴掃描）|
| Backend Docs | Docs | 可讀寫 | `backend/docs/` 目錄 |

## WORKSPACE_ROOT

從 `backend/.env` 的 `WORKSPACE_ROOT` 讀取。
安裝時由 `setup.sh --workspace /path` 設定。

支援多 Agent 場景：
```
WORKSPACE_ROOT=/home/david/project
→ 會掃描 clawd/, clawd-voice/, clawd-invest/ 等所有子目錄的 .md 檔
```

自動排除：`node_modules`, `.git`, `dist`, `build` 等。
ClawDashboard 目錄只讀 `records/` 子目錄。

---

# 三、Agents Sidebar

## 資料來源

`GET /api/agents` → 讀取 `OPENCLAW_CONFIG`（`openclaw.json`）
排除 `defaults` key，其餘每個 key 就是一個 Agent。

## 前端顯示邏輯

1. 呼叫 `/api/agents`（Agent 列表）
2. 呼叫 `/api/status`（含 agents map，各 Agent 獨立狀態）
3. 若 agents 為空 → 不顯示 Team Status
4. 優先以 `agentStates[name]` 判斷個別狀態
5. Fallback: `activeAgent` + global status

---

# 四、自動化規則

## 每次對話必做

1. 收到任務 → `PUT /api/status { state: "thinking" }`
2. 建立 task → `POST /api/webhook/message { stage: "received" }`
3. 開始執行 → `PUT /api/status { state: "acting" }`
4. task 進行 → `POST /api/webhook/message { stage: "started", taskId }`
5. task 完成 → `POST /api/webhook/message { stage: "completed", taskId }`
6. 回歸閒置 → `PUT /api/status { state: "idle" }`
7. 產出 `.md` 檔 → 放到 `backend/docs/`

## 多 Agent

- Main Agent 可用 `POST /api/status/agent { name, state }` 回報子 Agent 狀態
- 或要求子 Agent 自己打 API 回報

---

# 五、部署配置

## 網路模式

- `HOST=127.0.0.1` → 本地模式（預設）
- `HOST=0.0.0.0` → 區網模式
- 前端自動偵測 hostname，不需手動設定 API URL

## CORS

- `CORS_ORIGINS=*` → 允許所有 origin（預設，適合 local + LAN）
- `CORS_ORIGINS=http://host1,http://host2` → 白名單模式

## 啟動方式

| 指令 | 功能 |
|:---|:---|
| `./start.sh` | 前景啟動（開發用）|
| `./start.sh --bg` | PM2 背景常駐 |
| `./start.sh --stop` | 停止 |
| `./start.sh --boot` | 開機自啟 |
| `bash setup.sh --status` | 查看狀態 |
| `bash setup.sh --update` | 更新 + 重啟 |

---

# 結論

閉環系統：**Agent → Status → Task → Docs → UI**

Dashboard 不會主動偵測任何東西。
所有可視化都靠 Agent 主動回報 API 來驅動。
