import { context2d, createCanvas } from './imageUtils';

/**
 * Removes a plain, uniform background (a wall, floor, bedsheet or the white
 * backdrop of a product photo) by flood-filling inwards from the image edges
 * over pixels close to the dominant border colour. Areas inside the item that
 * happen to match (e.g. a white logo) are kept, because they don't touch the edge.
 *
 * Returns null when the background isn't plain enough for this to work well.
 */
export function removePlainBackground(source: HTMLCanvasElement): HTMLCanvasElement | null {
  const { width, height } = source;
  if (width < 16 || height < 16) return null;
  const image = context2d(source).getImageData(0, 0, width, height);
  const px = image.data;
  const count = width * height;

  // 1. Sample a band around the border.
  const band = Math.max(2, Math.floor(Math.min(width, height) / 50));
  const rs: number[] = [], gs: number[] = [], bs: number[] = [];
  let transparent = 0, total = 0;
  for (let y = 0; y < height; y++) {
    const fullRow = y < band || y >= height - band;
    for (let x = 0; x < width; x = !fullRow && x === band - 1 ? width - band : x + 1) {
      const i = (y * width + x) * 4;
      total++;
      if (px[i + 3] < 128) transparent++;
      else { rs.push(px[i]); gs.push(px[i + 1]); bs.push(px[i + 2]); }
    }
  }
  const alreadyTransparent = transparent / total > 0.5;

  let bgR = 0, bgG = 0, bgB = 0, tolerance2 = 0;
  if (!alreadyTransparent) {
    if (rs.length < 20) return null;
    const median = (v: number[]) => [...v].sort((a, b) => a - b)[v.length >> 1];
    bgR = median(rs); bgG = median(gs); bgB = median(bs);

    // 2. Adapt the tolerance to how noisy the background is.
    const distances = rs.map((r, k) => (r - bgR) ** 2 + (gs[k] - bgG) ** 2 + (bs[k] - bgB) ** 2).sort((a, b) => a - b);
    const p75 = Math.sqrt(distances[Math.floor(distances.length * 0.75)]);
    const tolerance = Math.min(Math.max(p75 * 2.5, 18), 55);
    tolerance2 = tolerance * tolerance;

    // The border must be mostly one colour, or this method isn't suitable.
    const matching = distances.filter((d) => d <= tolerance2).length;
    if (matching / distances.length < 0.6) return null;
  }

  const isBackground = (p: number) => {
    const i = p * 4;
    if (px[i + 3] < 128) return true;
    if (alreadyTransparent) return false;
    return (px[i] - bgR) ** 2 + (px[i + 1] - bgG) ** 2 + (px[i + 2] - bgB) ** 2 <= tolerance2;
  };

  // 3. Flood fill from the outer edge.
  const visited = new Uint8Array(count);
  const mask = new Uint8Array(count).fill(255);
  const stack: number[] = [];
  const seed = (p: number) => {
    if (!visited[p] && isBackground(p)) {
      visited[p] = 1;
      stack.push(p);
    }
  };
  for (let x = 0; x < width; x++) { seed(x); seed((height - 1) * width + x); }
  for (let y = 0; y < height; y++) { seed(y * width); seed(y * width + width - 1); }
  let backgroundCount = 0;
  while (stack.length) {
    const p = stack.pop()!;
    mask[p] = 0;
    backgroundCount++;
    const x = p % width, y = (p / width) | 0;
    if (x > 0) seed(p - 1);
    if (x < width - 1) seed(p + 1);
    if (y > 0) seed(p - width);
    if (y < height - 1) seed(p + width);
  }

  // 4. Something sensible must be left.
  const foreground = 1 - backgroundCount / count;
  if (foreground < 0.03 || foreground > 0.97) return null;

  // 5. Soften the edge and apply the mask.
  const out = createCanvas(width, height);
  const outImage = context2d(out).createImageData(width, height);
  const o = outImage.data;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const p = y * width + x;
      if (!mask[p]) continue;
      let sum = 0, n = 0;
      for (let dy = -1; dy <= 1; dy++) {
        const yy = y + dy;
        if (yy < 0 || yy >= height) continue;
        for (let dx = -1; dx <= 1; dx++) {
          const xx = x + dx;
          if (xx < 0 || xx >= width) continue;
          sum += mask[yy * width + xx];
          n++;
        }
      }
      const i = p * 4;
      o[i] = px[i]; o[i + 1] = px[i + 1]; o[i + 2] = px[i + 2];
      o[i + 3] = Math.min(px[i + 3], Math.round(sum / n));
    }
  }
  context2d(out).putImageData(outImage, 0, 0);
  return out;
}
