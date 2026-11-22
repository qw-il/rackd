// Rackd API: online product-photo search and an image fetch proxy.
//
// Runs inside the Vite dev server (see vite.config.ts) and the production
// server (server/server.mjs). API keys stay on the server and are never sent
// to the browser.
//
//   GET /api/config            -> { search: boolean, provider: string | null }
//   GET /api/search?q=...      -> { results: [{ thumbnail, image, title, source }] }
//   GET /api/image?url=...     -> the image bytes (lets the browser process
//                                 images from shops that block cross-origin use)

import { lookup } from 'node:dns/promises';
import { isIP } from 'node:net';

const MAX_IMAGE_BYTES = 15 * 1024 * 1024;
const MAX_REDIRECTS = 3;
const USER_AGENT = 'Mozilla/5.0 (compatible; RackdImageFetcher/1.0)';

export function createApiHandler(env = process.env) {
  return async function rackdApi(req, res, next) {
    const url = new URL(req.url ?? '/', 'http://localhost');
    if (!url.pathname.startsWith('/api/')) return next ? next() : notFound(res);
    if (req.method !== 'GET') return sendJSON(res, 405, { error: 'Method not allowed' });

    try {
      switch (url.pathname) {
        case '/api/config':
          return sendJSON(res, 200, { search: Boolean(providerFor(env)), provider: providerFor(env)?.name ?? null });
        case '/api/search':
          return await handleSearch(env, url, res);
        case '/api/image':
          return await handleImage(url, res);
        default:
          return notFound(res);
      }
    } catch (error) {
      console.error('[rackd api]', error);
      if (!res.headersSent) sendJSON(res, 502, { error: error?.message ?? 'Request failed' });
      else res.end();
    }
  };
}

// MARK: Search

function providerFor(env) {
  if (env.BRAVE_API_KEY) return { name: 'Brave Search', search: (q) => braveSearch(env.BRAVE_API_KEY, q) };
  if (env.SERPAPI_KEY) return { name: 'SerpApi', search: (q) => serpApiSearch(env.SERPAPI_KEY, q) };
  return null;
}

async function handleSearch(env, url, res) {
  const provider = providerFor(env);
  if (!provider) {
    return sendJSON(res, 503, { error: 'Online search isn\'t set up. Add BRAVE_API_KEY or SERPAPI_KEY to the server\'s .env file.' });
  }
  const query = (url.searchParams.get('q') ?? '').trim().slice(0, 200);
  if (!query) return sendJSON(res, 400, { error: 'Missing search text.' });

  const results = await provider.search(query);
  sendJSON(res, 200, { results });
}

async function braveSearch(apiKey, query) {
  const endpoint = new URL('https://api.search.brave.com/res/v1/images/search');
  endpoint.searchParams.set('q', query);
  endpoint.searchParams.set('count', '40');
  endpoint.searchParams.set('safesearch', 'strict');
  const response = await fetch(endpoint, {
    headers: { Accept: 'application/json', 'X-Subscription-Token': apiKey },
  });
  await assertOk(response);
  const data = await response.json();
  return (data.results ?? [])
    .map((r) => ({
      thumbnail: r.thumbnail?.src,
      image: r.properties?.url ?? null,
      title: r.title ?? '',
      source: r.source ?? '',
    }))
    .filter((r) => r.thumbnail);
}

async function serpApiSearch(apiKey, query) {
  const endpoint = new URL('https://serpapi.com/search.json');
  endpoint.searchParams.set('engine', 'google_images');
  endpoint.searchParams.set('q', query);
  endpoint.searchParams.set('safe', 'active');
  endpoint.searchParams.set('api_key', apiKey);
  const response = await fetch(endpoint);
  await assertOk(response);
  const data = await response.json();
  if (data.error) throw new Error(`Search failed: ${data.error}`);
  return (data.images_results ?? [])
    .slice(0, 40)
    .map((r) => ({ thumbnail: r.thumbnail, image: r.original ?? null, title: r.title ?? '', source: r.source ?? '' }))
    .filter((r) => r.thumbnail);
}

async function assertOk(response) {
  if (response.ok) return;
  if (response.status === 401 || response.status === 403) throw new Error('The search API key was rejected.');
  if (response.status === 429) throw new Error('Search rate limit reached. Try again shortly.');
  throw new Error(`Search service error (${response.status}).`);
}

// MARK: Image proxy

async function handleImage(url, res) {
  let target;
  try {
    target = new URL(url.searchParams.get('url') ?? '');
  } catch {
    return sendJSON(res, 400, { error: 'Invalid image URL.' });
  }

  let response;
  for (let hop = 0; ; hop++) {
    await assertPublicHttpUrl(target);
    response = await fetch(target, {
      redirect: 'manual',
      headers: { Accept: 'image/avif,image/webp,image/png,image/jpeg,image/*;q=0.8', 'User-Agent': USER_AGENT },
      signal: AbortSignal.timeout(15000),
    });
    const location = response.headers.get('location');
    if (response.status >= 300 && response.status < 400 && location) {
      if (hop >= MAX_REDIRECTS) return sendJSON(res, 502, { error: 'Too many redirects.' });
      target = new URL(location, target);
      continue;
    }
    break;
  }

  const type = response.headers.get('content-type') ?? '';
  if (!response.ok || !type.startsWith('image/')) {
    return sendJSON(res, 502, { error: 'That address didn\'t return an image.' });
  }
  const declared = Number(response.headers.get('content-length') ?? 0);
  if (declared > MAX_IMAGE_BYTES) return sendJSON(res, 413, { error: 'Image too large.' });

  const chunks = [];
  let total = 0;
  for await (const chunk of response.body) {
    total += chunk.length;
    if (total > MAX_IMAGE_BYTES) return sendJSON(res, 413, { error: 'Image too large.' });
    chunks.push(chunk);
  }
  res.writeHead(200, {
    'Content-Type': type,
    'Content-Length': total,
    'Cache-Control': 'private, max-age=3600',
    'X-Content-Type-Options': 'nosniff',
  });
  res.end(Buffer.concat(chunks.map((c) => Buffer.from(c))));
}

/** Blocks requests to localhost / private networks (SSRF protection). */
async function assertPublicHttpUrl(target) {
  if (target.protocol !== 'http:' && target.protocol !== 'https:') throw new Error('Only http(s) images are allowed.');
  const host = target.hostname.replace(/^\[|\]$/g, '');
  const addresses = isIP(host) ? [{ address: host }] : await lookup(host, { all: true });
  if (addresses.length === 0 || addresses.some(({ address }) => isPrivateAddress(address))) {
    throw new Error('That image address isn\'t allowed.');
  }
}

function isPrivateAddress(address) {
  if (address.startsWith('::ffff:')) address = address.slice(7);
  if (isIP(address) === 4) {
    const [a, b] = address.split('.').map(Number);
    return (
      a === 0 || a === 10 || a === 127 || a >= 224 ||
      (a === 100 && b >= 64 && b <= 127) ||
      (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) ||
      (a === 192 && b === 168) ||
      (a === 198 && (b === 18 || b === 19))
    );
  }
  const lower = address.toLowerCase();
  return lower === '::' || lower === '::1' || lower.startsWith('fc') || lower.startsWith('fd') || lower.startsWith('fe8') ||
    lower.startsWith('fe9') || lower.startsWith('fea') || lower.startsWith('feb');
}

// MARK: Helpers

function sendJSON(res, status, body) {
  const json = JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(json);
}

function notFound(res) {
  sendJSON(res, 404, { error: 'Not found' });
}
