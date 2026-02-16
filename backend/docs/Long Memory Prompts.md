# Long Memory Prompts

所有使用者的對話都必須建立一個對應 Task (title 為第一行摘要 ≤120 字，description 為全文)，並透過 webhook/api/webhook/message 依序觸發 received → started → completed 來推動任務狀態 todo → in_progress → done，同時狀態燈依規則自動切換 thinking → acting → idle，Status 為單一真實來源（SQLite status 表），Agents 清單由 openclaw.json 動態讀取（排除 defaults，無 agent 則隱藏 Team Status)，所有Task最後都要產出md檔案放到backend/docs做記錄

Workspace 下所有 .md 會自動掃描並顯示於 Docs（workspace 視為 System、backend/docs 視為 Docs），整體原則是：所有 Agent 行為都必須可視化、可追蹤、可回放，形成 Agent → Status → Task → Docs → UI 的閉環系統。

-   實測流程（含狀態燈與測試句子）：
-   測試句子：請幫我整理本週會議重點並產出摘要
-   Step 1：收到任務 → thinking - PUT /api/status payload {
    "state":"thinking" }
-   Step 2：建立 task（todo） - POST /api/webhook/message payload {
    "text":"請幫我整理本週會議重點並產出摘要", "stage":"received" }
-   Step 3：開始執行 → acting - PUT /api/status payload {
    "state":"acting" }
-   Step 4：task 進度 → in_progress - POST /api/webhook/message payload
    { "taskId":`<id>`{=html}, "stage":"started" }
-   Step 5：task 完成 → done - POST /api/webhook/message payload {
    "taskId":`<id>`{=html}, "stage":"completed" }
-   Step 6：完成 → idle - PUT /api/status payload { "state":"idle" }
-   (Optional) Multi-Agent Status:
    -   Agent A Thinking: POST /api/status/agent { "name": "Architect", "state": "thinking" }
    -   Agent B Acting: POST /api/status/agent { "name": "Coder", "state": "acting" }
