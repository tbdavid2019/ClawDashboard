// PM2 Ecosystem Configuration
// Usage: pm2 start pm2.ecosystem.config.js

const path = require('path');
const dotenv = require('dotenv');

// Read backend .env for HOST config
const envPath = path.join(__dirname, 'backend', '.env');
const env = dotenv.config({ path: envPath });
const HOST = process.env.HOST || '127.0.0.1';
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
                NODE_ENV: 'production'
            }
        },
        {
            name: 'claw-frontend',
            cwd: path.join(__dirname, 'frontend'),
            script: 'node_modules/.bin/vite',
            args: `--host ${VITE_HOST}`,
            watch: false,
            autorestart: true,
            max_restarts: 10,
            restart_delay: 3000,
        }
    ]
};
