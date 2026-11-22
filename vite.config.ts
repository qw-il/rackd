import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import { createApiHandler } from './server/api.mjs';

export default defineConfig(({ mode }) => {
  // Expose BRAVE_API_KEY / SERPAPI_KEY from .env to the dev API (server-side only).
  Object.assign(process.env, loadEnv(mode, process.cwd(), ''));

  return {
    plugins: [
      react(),
      {
        name: 'rackd-api',
        configureServer(server) {
          server.middlewares.use(createApiHandler(process.env));
        },
        configurePreviewServer(server) {
          server.middlewares.use(createApiHandler(process.env));
        },
      },
    ],
    optimizeDeps: {
      // These ship their own WASM/worker files; let them load as-is.
      exclude: ['@imgly/background-removal', '@huggingface/transformers'],
    },
    build: {
      chunkSizeWarningLimit: 4000,
    },
  };
});
