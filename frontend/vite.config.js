import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  base: '/',
  server: {
    port: parseInt(process.env.VITE_PORT || '5173'),
    strictPort: true,  // 不要靜默跳 port，衝突就報錯
    host: process.env.VITE_HOST || '127.0.0.1',
  },
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
  }
})
