export const MAX_DIMENSION = 1600;

export function createCanvas(width: number, height: number): HTMLCanvasElement {
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.round(width));
  canvas.height = Math.max(1, Math.round(height));
  return canvas;
}

export function context2d(canvas: HTMLCanvasElement): CanvasRenderingContext2D {
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  if (!ctx) throw new Error('Canvas is not supported in this browser.');
  return ctx;
}

/**
 * Decodes an image (respecting EXIF orientation) onto a canvas, scaled so its
 * longest side is at most `maxDimension`.
 */
export async function blobToCanvas(blob: Blob, maxDimension = MAX_DIMENSION): Promise<HTMLCanvasElement> {
  const url = URL.createObjectURL(blob);
  try {
    const img = new Image();
    img.decoding = 'async';
    img.src = url;
    try {
      await img.decode();
    } catch {
      throw new Error('This file couldn\'t be opened as an image. HEIC photos may need converting to JPEG first.');
    }
    const longest = Math.max(img.naturalWidth, img.naturalHeight);
    const factor = longest > maxDimension ? maxDimension / longest : 1;
    const canvas = createCanvas(img.naturalWidth * factor, img.naturalHeight * factor);
    const ctx = context2d(canvas);
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
    return canvas;
  } finally {
    URL.revokeObjectURL(url);
  }
}

export function canvasToBlob(canvas: HTMLCanvasElement, type = 'image/png', quality?: number): Promise<Blob> {
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => (blob ? resolve(blob) : reject(new Error('Couldn\'t encode image.'))), type, quality);
  });
}

/**
 * Cleans up a segmentation result: drops faint haze and small stray islands,
 * keeping the main shape(s) – e.g. both shoes of a pair – and their soft edges.
 */
export function cleanupMask(canvas: HTMLCanvasElement): void {
  const { width, height } = canvas;
  const ctx = context2d(canvas);
  const image = ctx.getImageData(0, 0, width, height);
  const { data } = image;
  const count = width * height;

  // Label 4-connected components of solid pixels.
  const labels = new Int32Array(count).fill(-1);
  const areas: number[] = [];
  const stack: number[] = [];
  for (let start = 0; start < count; start++) {
    if (labels[start] !== -1 || data[start * 4 + 3] <= 128) continue;
    const label = areas.length;
    let area = 0;
    labels[start] = label;
    stack.push(start);
    while (stack.length) {
      const p = stack.pop()!;
      area++;
      const x = p % width;
      const neighbours = [x > 0 ? p - 1 : -1, x < width - 1 ? p + 1 : -1, p - width, p + width];
      for (const n of neighbours) {
        if (n >= 0 && n < count && labels[n] === -1 && data[n * 4 + 3] > 128) {
          labels[n] = label;
          stack.push(n);
        }
      }
    }
    areas.push(area);
  }
  if (!areas.length) return;
  const largest = Math.max(...areas);
  const keep = areas.map((a) => a >= largest * 0.08);

  // Remove dropped islands; keep soft edge pixels only next to kept shapes.
  const kept = (p: number) => labels[p] >= 0 && keep[labels[p]];
  for (let p = 0; p < count; p++) {
    const i = p * 4 + 3;
    if (labels[p] >= 0) {
      if (!keep[labels[p]]) data[i] = 0;
      continue;
    }
    if (data[i] === 0) continue;
    const x = p % width;
    const nearKept =
      (x > 0 && kept(p - 1)) || (x < width - 1 && kept(p + 1)) ||
      (p >= width && kept(p - width)) || (p + width < count && kept(p + width));
    if (!nearKept || data[i] < 40) data[i] = 0;
  }
  ctx.putImageData(image, 0, 0);
}

/** Fraction of pixels that are (mostly) opaque. */
export function opaqueFraction(canvas: HTMLCanvasElement): number {
  const { data } = context2d(canvas).getImageData(0, 0, canvas.width, canvas.height);
  let opaque = 0;
  for (let i = 3; i < data.length; i += 4) if (data[i] > 128) opaque++;
  return opaque / (canvas.width * canvas.height);
}

/**
 * Crops transparent margins away, leaving a small border. Rows/columns with
 * only a few stray opaque pixels are ignored so specks don't widen the crop.
 * Returns null if nothing is left.
 */
export function cropToContent(canvas: HTMLCanvasElement, margin = 4): HTMLCanvasElement | null {
  const { width, height } = canvas;
  const { data } = context2d(canvas).getImageData(0, 0, width, height);
  const cols = new Uint32Array(width);
  const rows = new Uint32Array(height);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (data[(y * width + x) * 4 + 3] > 64) {
        cols[x]++;
        rows[y]++;
      }
    }
  }
  const minInCol = Math.max(1, Math.round(height * 0.01));
  const minInRow = Math.max(1, Math.round(width * 0.01));
  let minX = cols.findIndex((c) => c >= minInCol);
  let maxX = cols.findLastIndex((c) => c >= minInCol);
  let minY = rows.findIndex((c) => c >= minInRow);
  let maxY = rows.findLastIndex((c) => c >= minInRow);
  if (minX < 0 || minY < 0) return null;
  minX = Math.max(0, minX - margin);
  minY = Math.max(0, minY - margin);
  maxX = Math.min(width - 1, maxX + margin);
  maxY = Math.min(height - 1, maxY + margin);
  const out = createCanvas(maxX - minX + 1, maxY - minY + 1);
  context2d(out).drawImage(canvas, minX, minY, out.width, out.height, 0, 0, out.width, out.height);
  return out;
}

/** Flattens transparency onto white (classifiers expect opaque images). */
export function onWhite(canvas: HTMLCanvasElement): HTMLCanvasElement {
  const out = createCanvas(canvas.width, canvas.height);
  const ctx = context2d(out);
  ctx.fillStyle = '#fff';
  ctx.fillRect(0, 0, out.width, out.height);
  ctx.drawImage(canvas, 0, 0);
  return out;
}
