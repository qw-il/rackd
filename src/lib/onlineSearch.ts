export interface SearchResult {
  thumbnail: string;
  image: string | null;
  title: string;
  source: string;
}

export interface SearchConfig {
  search: boolean;
  provider: string | null;
}

/** Whether the server has a search key configured. False on static hosting. */
export async function getSearchConfig(): Promise<SearchConfig> {
  try {
    const response = await fetch('/api/config');
    if (!response.ok) return { search: false, provider: null };
    return (await response.json()) as SearchConfig;
  } catch {
    return { search: false, provider: null };
  }
}

export function buildQuery(brand: string, type: string, color: string, preferProductShots: boolean) {
  const parts = [brand, color, type].map((s) => s.trim()).filter(Boolean);
  if (preferProductShots) parts.push('product photo white background');
  return parts.join(' ');
}

export async function searchImages(query: string): Promise<SearchResult[]> {
  const response = await fetch(`/api/search?q=${encodeURIComponent(query)}`);
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.error ?? `Search failed (${response.status}).`);
  return body.results as SearchResult[];
}

/** Downloads the full image through our server (falls back to the thumbnail). */
export async function downloadResult(result: SearchResult): Promise<Blob> {
  for (const url of [result.image, result.thumbnail]) {
    if (!url) continue;
    try {
      const response = await fetch(`/api/image?url=${encodeURIComponent(url)}`);
      if (response.ok) {
        const blob = await response.blob();
        if (blob.type.startsWith('image/')) return blob;
      }
    } catch {
      // try the next URL
    }
  }
  throw new Error('Couldn\'t download that image. Try another one.');
}
