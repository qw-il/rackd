// Copies the background-removal model + ONNX runtime files from
// @imgly/background-removal-data into public/imgly so the app serves them
// itself instead of depending on imgly's CDN. Only the "small" model and the
// plain WASM runtimes are copied (~85 MB) to keep deployments lean.
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const sourceDir = join(root, 'node_modules/@imgly/background-removal-data/dist');
const targetDir = join(root, 'public/imgly');

const wanted = [
  '/models/small',
  '/onnxruntime-web/ort-wasm.wasm',
  '/onnxruntime-web/ort-wasm-simd.wasm',
  '/onnxruntime-web/ort-wasm-threaded.wasm',
  '/onnxruntime-web/ort-wasm-simd-threaded.wasm',
];

if (!existsSync(join(sourceDir, 'resources.json'))) {
  console.warn('[rackd] @imgly/background-removal-data not installed; the app will use imgly\'s CDN.');
  process.exit(0);
}

const resources = JSON.parse(readFileSync(join(sourceDir, 'resources.json'), 'utf8'));
const marker = join(targetDir, 'resources.json');
const subset = Object.fromEntries(wanted.filter((key) => resources[key]).map((key) => [key, resources[key]]));

if (existsSync(marker) && readFileSync(marker, 'utf8') === JSON.stringify(subset)) {
  process.exit(0); // already up to date
}

rmSync(targetDir, { recursive: true, force: true });
mkdirSync(targetDir, { recursive: true });
let bytes = 0;
for (const entry of Object.values(subset)) {
  for (const chunk of entry.chunks) {
    cpSync(join(sourceDir, chunk.hash), join(targetDir, chunk.hash));
  }
  bytes += entry.size;
}
writeFileSync(marker, JSON.stringify(subset));
console.log(`[rackd] Copied background-removal assets (${(bytes / 1e6).toFixed(0)} MB) to public/imgly`);
