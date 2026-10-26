import { defineConfig } from 'vitest/config';
export default defineConfig({
  test: { include: ['tests/*.test.ts', 'tests/*.test.tsx'], environment: 'node' },
  server: { host: '127.0.0.1', port: 5173, strictPort: true, fs: { allow: ['..'] } },
});
