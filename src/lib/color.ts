import { context2d, createCanvas } from './imageUtils';

const PALETTE: [string, number, number, number][] = [
  ['Black', 20, 20, 22], ['Charcoal', 60, 62, 66], ['Gray', 128, 128, 130], ['Light Gray', 196, 196, 198],
  ['White', 245, 245, 243], ['Cream', 240, 230, 205], ['Beige', 210, 190, 160], ['Tan', 190, 150, 105],
  ['Brown', 115, 75, 45], ['Burgundy', 120, 25, 40], ['Red', 200, 35, 40], ['Pink', 235, 150, 170],
  ['Orange', 235, 125, 40], ['Mustard', 205, 165, 45], ['Yellow', 245, 215, 60], ['Olive', 110, 115, 55],
  ['Green', 50, 135, 70], ['Mint', 165, 220, 190], ['Teal', 30, 125, 130], ['Light Blue', 150, 190, 230],
  ['Denim', 75, 105, 145], ['Blue', 40, 85, 185], ['Navy', 30, 40, 80], ['Purple', 110, 60, 145],
  ['Lavender', 190, 170, 220],
];

export interface DetectedColor {
  name: string;
  hex: string;
}

/** Dominant colour of the item, ignoring transparent (removed) background. */
export function dominantColor(source: HTMLCanvasElement): DetectedColor | null {
  const side = 48;
  const small = createCanvas(side, side);
  const ctx = context2d(small);
  ctx.drawImage(source, 0, 0, side, side);
  const { data } = ctx.getImageData(0, 0, side, side);

  // Bucket opaque pixels (4 bits per channel) and take the most common bucket.
  const buckets = new Map<number, { n: number; r: number; g: number; b: number }>();
  for (let i = 0; i < data.length; i += 4) {
    if (data[i + 3] < 200) continue;
    const [r, g, b] = [data[i], data[i + 1], data[i + 2]];
    const key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
    const bucket = buckets.get(key) ?? { n: 0, r: 0, g: 0, b: 0 };
    bucket.n++; bucket.r += r; bucket.g += g; bucket.b += b;
    buckets.set(key, bucket);
  }
  const top = [...buckets.values()].sort((a, b) => b.n - a.n)[0];
  if (!top) return null;

  const r = top.r / top.n, g = top.g / top.n, b = top.b / top.n;
  const hex = '#' + [r, g, b].map((v) => Math.round(v).toString(16).padStart(2, '0')).join('').toUpperCase();
  return { name: nearestName(r, g, b), hex };
}

function nearestName(r: number, g: number, b: number): string {
  // "Redmean" weighted distance – cheap and closer to perception than plain RGB.
  let best = PALETTE[0][0], bestDistance = Infinity;
  for (const [name, pr, pg, pb] of PALETTE) {
    const rMean = (r + pr) / 2;
    const d = (2 + rMean / 256) * (r - pr) ** 2 + 4 * (g - pg) ** 2 + (2 + (255 - rMean) / 256) * (b - pb) ** 2;
    if (d < bestDistance) { bestDistance = d; best = name; }
  }
  return best;
}
