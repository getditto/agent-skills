import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './browser', timeout: 30000, workers: 1,
  use: { baseURL: 'http://127.0.0.1:4179', trace: 'off' },
  webServer: { command: 'npx vite --host 127.0.0.1 --port 4179 --strictPort', url: 'http://127.0.0.1:4179', reuseExistingServer: false },
});
