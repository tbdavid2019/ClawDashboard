// PM2 Ecosystem Configuration
// Usage: pm2 start pm2.ecosystem.config.js

const path = require('path');
const fs = require('fs');

// Read backend .env manually (no dotenv dependency needed)
const envPath = path.join(__dirname, 'backend', '.env');
let HOST = '127.0.0.1';
let PORT = '3001';
let FRONTEND_PORT = '5173';

if (fs.existsSync(envPath)) {
    const envContent = fs.readFileSync(envPath, 'utf8');
    const hostMatch = envContent.match(/^HOST=(.+)$/m);
    const portMatch = envContent.match(/^PORT=(.+)$/m);
    const fportMatch = envContent.match(/^FRONTEND_PORT=(.+)$/m);
    if (hostMatch) HOST = hostMatch[1].trim();
    if (portMatch) PORT = portMatch[1].trim();
    if (fportMatch) FRONTEND_PORT = fportMatch[1].trim();
}

const VITE_HOST = HOST === '0.0.0.0' ? '0.0.0.0' : '127.0.0.1';

module.exports = {
    apps: [
        {
            name: 'claw-backend',
            cwd: path.join(__dirname, 'backend'),
            script: 'server.js',
            watch: false,
            autorestart: true,
            max_restarts: 10,
            restart_delay: 3000,
            env: {
                NODE_ENV: 'production',
                HOST: HOST,
                PORT: PORT,
            }
        },
        {
            name: 'claw-frontend',
            cwd: path.join(__dirname, 'frontend'),
            script: 'node_modules/.bin/vite',
            watch: false,
            autorestart: true,
            max_restarts: 10,
            restart_delay: 3000,
            env: {
                VITE_HOST: VITE_HOST,
                VITE_PORT: FRONTEND_PORT,
            }
        }
    ]
};
