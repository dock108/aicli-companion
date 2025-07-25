import { defineConfig } from 'vitest/config';
import { resolve } from 'path';

export default defineConfig({
  test: {
    environment: 'happy-dom',
    globals: true,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html', 'clover'],
      include: ['src/**/*.{js,ts}'],
      exclude: [
        'src-tauri/**',
        'coverage/**',
        'test/**',
        'vitest.config.js',
        'vite.config.js',
        '**/*.d.ts',
        '**/*.config.js',
        '**/mockServiceWorker.js'
      ],
      all: true,
      branches: 80,
      functions: 80,
      lines: 80,
      statements: 80
    },
    setupFiles: ['./test/setup.js']
  },
  resolve: {
    alias: {
      '@': resolve(__dirname, './src'),
      '@tauri-apps/api/core': resolve(__dirname, './test/mocks/tauri-api-core.js'),
      '@tauri-apps/plugin-dialog': resolve(__dirname, './test/mocks/tauri-plugin-dialog.js'),
      '@tauri-apps/api/path': resolve(__dirname, './test/mocks/tauri-api-path.js'),
      'qrcode': resolve(__dirname, './test/mocks/qrcode.js')
    }
  }
});