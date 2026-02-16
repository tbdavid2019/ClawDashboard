// Frontend Configuration
export const BOT_NAME = "Claw";
export const DASHBOARD_TITLE = "Claw Dashboard";

// API Base URL
// Auto-detect: uses the same hostname the browser is on, with backend port 3001.
// Override via VITE_API_URL env var if needed (e.g., VITE_API_URL=http://10.0.0.10:3001)
const BACKEND_PORT = import.meta.env.VITE_BACKEND_PORT || "3001";
export const API_BASE_URL =
  import.meta.env.VITE_API_URL ||
  `${window.location.protocol}//${window.location.hostname}:${BACKEND_PORT}`;

export const FEATURES = {
  ENABLE_MODEL_USAGE: false
};
