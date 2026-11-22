// Production server: serves the built app from dist/ and the /api routes.
//   npm run build && npm start
import { createReadStream, existsSync, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createApiHandler } from './api.mjs';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
if (existsSync(join(root, '.env'))) process.loadEnvFile(join(root, '.env'));

const dist = join(root, 'dist');
const port = Number(process.env.PORT ?? 8787);
const api = createApiHandler(process.env);

const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
};

if (!existsSync(join(dist, 'index.html'))) {
  console.error('dist/ not found – run `npm run build` first.');
  process.exit(1);
}

createServer((req, res) => {
  const path = decodeURIComponent(new URL(req.url ?? '/', 'http://localhost').pathname);
  if (path.startsWith('/api/')) return api(req, res);

  let file = normalize(join(dist, path));
  if (!file.startsWith(dist + sep) && file !== dist) {
    res.writeHead(403).end();
    return;
  }
  if (!existsSync(file) || statSync(file).isDirectory()) file = join(dist, 'index.html'); // SPA fallback

  const ext = extname(file);
  // Hashed model chunks under /imgly/ have no extension and never change.
  const immutable = path.startsWith('/assets/') || path.startsWith('/imgly/');
  res.writeHead(200, {
    'Content-Type': types[ext] ?? 'application/octet-stream',
    'Cache-Control': immutable ? 'public, max-age=31536000, immutable' : 'no-cache',
  });
  createReadStream(file).pipe(res);
}).listen(port, () => {
  console.log(`Rackd running at http://localhost:${port}`);
});
