# Claw Dashboard — Troubleshooting Guide
# (For AI Agents and Human Operators)

------------------------------------------------------------------------

## Port Conflict (Port 被佔用)

### Symptom
- `Port 5173 is in use, trying another one...`
- `EADDRINUSE: address already in use :::3001`
- ERR_CONNECTION_REFUSED on expected port

### Cause
Another process is using port 3001 or 5173. Vite may silently jump to 5174/5175.

### Fix

```bash
# Find what's using the port
lsof -i:5173
lsof -i:3001

# Kill it
kill <PID>

# Or use the built-in script (auto-kills conflicting processes)
./start.sh --stop
./start.sh --bg
```

**Important**: `vite.config.js` has `strictPort: true`, so Vite will ERROR instead of silently switching ports. This is by design.

------------------------------------------------------------------------

## ERR_CONNECTION_REFUSED (連線被拒)

### Symptom
Browser shows ERR_CONNECTION_REFUSED at http://10.0.0.10:5173

### Checklist

1. **Is the service running?**
   ```bash
   pm2 status
   ```

2. **Is it bound to 0.0.0.0 (not 127.0.0.1)?**
   ```bash
   cat backend/.env | grep HOST
   # Should be: HOST=0.0.0.0 for LAN access
   ```

3. **Is the firewall blocking?**
   ```bash
   # Linux (ufw)
   sudo ufw status
   sudo ufw allow 5173
   sudo ufw allow 3001

   # Linux (firewalld)
   sudo firewall-cmd --add-port=5173/tcp --permanent
   sudo firewall-cmd --add-port=3001/tcp --permanent
   sudo firewall-cmd --reload
   ```

4. **Can the host actually reach the IP?**
   ```bash
   ping <IP>
   curl http://<IP>:3001/
   ```

------------------------------------------------------------------------

## Frontend Can't Reach Backend API (前端連不上 API)

### Symptom
Dashboard loads but shows no data, console shows CORS or network errors.

### Cause
Frontend is auto-detecting the wrong API URL, or CORS is blocking.

### Fix

1. **Check browser console** for the actual API URL being called.
2. **The frontend auto-detects** `window.location.hostname` + port 3001.
   If the browser URL is `http://10.0.0.10:5173`, API goes to `http://10.0.0.10:3001`.
3. **Override manually** if needed: create `frontend/.env`:
   ```bash
   VITE_API_URL=http://10.0.0.10:3001
   ```
4. **CORS**: backend defaults to `CORS_ORIGINS=*` (allow all). If restricted:
   ```bash
   # backend/.env
   CORS_ORIGINS=http://10.0.0.10:5173,http://localhost:5173
   ```

------------------------------------------------------------------------

## PM2 Not Found

### Symptom
`command not found: pm2`

### Fix
```bash
npm install -g pm2

# If permission error on Linux:
sudo npm install -g pm2
```

------------------------------------------------------------------------

## Service Won't Start After Reboot (重開機後服務沒啟動)

### Cause
PM2 startup not configured, or state not saved.

### Fix
```bash
# 1. Start services
./start.sh --bg

# 2. Setup boot startup (may need sudo)
pm2 startup
# Run the command it prints (starts with sudo env...)

# 3. Save current state
pm2 save
```

------------------------------------------------------------------------

## Node.js Version Too Old

### Symptom
Syntax errors, import errors, or npm install failures.

### Required
Node.js >= 18

### Check & Upgrade
```bash
node -v

# Linux (NodeSource)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# macOS
brew install node

# Any OS (nvm)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
nvm install 20
```

------------------------------------------------------------------------

## Raspberry Pi Specific

- Use Node.js ARM builds (NodeSource supports armv7l/aarch64)
- Memory may be limited — PM2 is lightweight, should be fine
- If `npm install` fails on native modules, try: `npm install --build-from-source`
- Ensure swap is enabled if < 1GB RAM

------------------------------------------------------------------------

## Quick Diagnostic Commands

```bash
# Service status
pm2 status

# Live logs
pm2 logs

# Backend only
pm2 logs claw-backend

# Frontend only
pm2 logs claw-frontend

# What's using ports
lsof -i:3001
lsof -i:5173

# Network config
cat backend/.env

# Restart everything
pm2 restart all

# Nuclear: stop, delete, reinstall
pm2 stop all && pm2 delete all
./start.sh --bg
```
