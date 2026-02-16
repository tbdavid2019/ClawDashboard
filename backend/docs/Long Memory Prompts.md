# ClawDashboard — Agent 整合指令

你（Agent）在每次接到使用者任務時，**必須同步更新 ClawDashboard**。
Dashboard 是被動的，不會主動偵測你的狀態。你必須主動回報。

## Dashboard API 位址

```
http://localhost:3001
```

如果在區網模式，請替換為實際 IP（例如 `http://10.0.0.10:3001`）。

---

## 你在每次對話中必須做的事

### Step 1：收到任務 → 回報 thinking + 建立 task

```bash
# 1a. 狀態燈 → thinking
curl -X PUT http://localhost:3001/api/status \
  -H "Content-Type: application/json" \
  -d '{"state": "thinking", "activeAgent": "你的名字"}'

# 1b. 建立 task
curl -X POST http://localhost:3001/api/webhook/message \
  -H "Content-Type: application/json" \
  -d '{"text": "使用者的任務摘要（第一行，≤120字）", "stage": "received"}'
```

回傳會包含 `task.id`，記住它用於後續步驟。

### Step 2：開始執行 → 回報 acting + task 進度

```bash
# 2a. 狀態燈 → acting
curl -X PUT http://localhost:3001/api/status \
  -H "Content-Type: application/json" \
  -d '{"state": "acting", "activeAgent": "你的名字"}'

# 2b. task → in_progress
curl -X POST http://localhost:3001/api/webhook/message \
  -H "Content-Type: application/json" \
  -d '{"stage": "started", "taskId": <task.id>}'
```

### Step 3：任務完成 → 回報 idle + task 完成

```bash
# 3a. task → done
curl -X POST http://localhost:3001/api/webhook/message \
  -H "Content-Type: application/json" \
  -d '{"stage": "completed", "taskId": <task.id>}'

# 3b. 狀態燈 → idle
curl -X PUT http://localhost:3001/api/status \
  -H "Content-Type: application/json" \
  -d '{"state": "idle"}'
```

### Step 4：產出文件記錄

任務完成後，將結果摘要寫成 `.md` 檔案放到 `backend/docs/` 目錄。
這些檔案會自動出現在 Dashboard 的 Docs tab。

---

## 多 Agent 場景（如果你是 Main Agent）

如果你管理多個子 Agent（例如 clawd-voice、clawd-invest），你必須：

1. **要求每個子 Agent 自己回報狀態**：

```bash
# 子 Agent 回報個別狀態
curl -X POST http://localhost:3001/api/status/agent \
  -H "Content-Type: application/json" \
  -d '{"name": "clawd-voice", "state": "acting"}'
```

2. **或者由你代替子 Agent 回報**（如果子 Agent 不支持）：

每次你把任務分配給子 Agent 時：

```bash
# 分配給 clawd-voice
curl -X POST http://localhost:3001/api/status/agent \
  -H "Content-Type: application/json" \
  -d '{"name": "clawd-voice", "state": "thinking"}'

# clawd-voice 開始工作
curl -X POST http://localhost:3001/api/status/agent \
  -H "Content-Type: application/json" \
  -d '{"name": "clawd-voice", "state": "acting"}'

# clawd-voice 完成
curl -X POST http://localhost:3001/api/status/agent \
  -H "Content-Type: application/json" \
  -d '{"name": "clawd-voice", "state": "idle"}'
```

---

## 三種狀態

| 狀態 | 意思 | 何時設定 |
|:---|:---|:---|
| `idle` | 閒置，等待指令 | 任務完成後 |
| `thinking` | 收到任務，正在規劃 | 剛收到使用者訊息時 |
| `acting` | 正在執行操作 | 開始寫程式、查資料、呼叫工具時 |

---

## Agent 列表來源

Dashboard sidebar 的 Agent 列表從 `openclaw.json` 讀取。
你不需要透過 API 註冊 Agent，只要在 `openclaw.json` 裡有配置就會自動出現。

---

## 核心原則

1. **所有 Agent 行為都必須可視化** — 不要悄悄做事，每個動作都要回報
2. **Dashboard 是被動的** — 你不打 API，它就不知道你在幹嘛
3. **閉環：Agent → Status → Task → Docs → UI** — 每次任務都要走完這個循環
