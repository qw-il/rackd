import type { Category } from './categories';
import { onWhite } from './imageUtils';

export interface Classification {
  category: Category;
  /** 0…1. Low values mean it's a guess. */
  confidence: number;
  /** Readable label, e.g. "Jeans". */
  label?: string;
}

/** Labels for zero-shot classification with CLIP, mapped to categories. */
const LABELS: [string, Category][] = [
  ['t-shirt', 'tops'], ['shirt', 'tops'], ['blouse', 'tops'], ['sweater', 'tops'], ['hoodie', 'tops'],
  ['sweatshirt', 'tops'], ['tank top', 'tops'], ['polo shirt', 'tops'], ['cardigan', 'tops'],
  ['jeans', 'bottoms'], ['trousers', 'bottoms'], ['shorts', 'bottoms'], ['skirt', 'bottoms'],
  ['leggings', 'bottoms'], ['sweatpants', 'bottoms'],
  ['dress', 'dresses'], ['jumpsuit', 'dresses'],
  ['jacket', 'outerwear'], ['coat', 'outerwear'], ['blazer', 'outerwear'], ['puffer jacket', 'outerwear'],
  ['raincoat', 'outerwear'],
  ['sneakers', 'shoes'], ['boots', 'shoes'], ['sandals', 'shoes'], ['high heels', 'shoes'],
  ['loafers', 'shoes'], ['dress shoes', 'shoes'],
  ['handbag', 'bags'], ['backpack', 'bags'], ['tote bag', 'bags'], ['clutch bag', 'bags'],
  ['hat', 'accessories'], ['cap', 'accessories'], ['scarf', 'accessories'], ['belt', 'accessories'],
  ['sunglasses', 'accessories'], ['watch', 'accessories'], ['necklace', 'accessories'],
  ['tie', 'accessories'], ['socks', 'accessories'],
];

type ClipResult = { label: string; score: number }[];
type ClipPipeline = (image: unknown, labels: string[], options: { hypothesis_template: string }) => Promise<ClipResult>;

let clipPromise: Promise<{ classify: ClipPipeline; fromCanvas: (c: HTMLCanvasElement) => unknown }> | null = null;

/** Loads CLIP (~90 MB, cached by the browser after the first time). */
function loadClip() {
  clipPromise ??= (async () => {
    const { pipeline, RawImage } = await import('@huggingface/transformers');
    const classify = await pipeline('zero-shot-image-classification', 'Xenova/clip-vit-base-patch32', {
      dtype: 'q8',
    });
    return {
      classify: classify as unknown as ClipPipeline,
      fromCanvas: (canvas: HTMLCanvasElement) => RawImage.fromCanvas(canvas),
    };
  })();
  clipPromise.catch(() => {
    clipPromise = null; // allow a retry later (e.g. after going online)
  });
  return clipPromise;
}

export async function classifyClothing(
  cutout: HTMLCanvasElement,
  onStatus?: (message: string) => void,
): Promise<Classification> {
  try {
    onStatus?.('Loading clothing recogniser (first time only)…');
    const clip = await loadClip();
    onStatus?.('Sorting into a category…');
    const results = await clip.classify(clip.fromCanvas(onWhite(cutout)), LABELS.map(([label]) => label), {
      hypothesis_template: 'a product photo of {}',
    });

    const totals = new Map<Category, number>();
    const best = new Map<Category, { label: string; score: number }>();
    for (const { label, score } of results) {
      const category = LABELS.find(([l]) => l === label)?.[1];
      if (!category) continue;
      totals.set(category, (totals.get(category) ?? 0) + score);
      if (score > (best.get(category)?.score ?? 0)) best.set(category, { label, score });
    }
    const [category, confidence] = [...totals.entries()].sort((a, b) => b[1] - a[1])[0];
    const label = best.get(category)?.label;
    return { category, confidence, label: label && label[0].toUpperCase() + label.slice(1) };
  } catch (error) {
    console.warn('[rackd] Clothing recogniser unavailable, guessing from shape:', error);
    return guessFromShape(cutout);
  }
}

/** Wide & short → shoes, tall & narrow → bottoms, otherwise a top. */
function guessFromShape(canvas: HTMLCanvasElement): Classification {
  const aspect = canvas.height / canvas.width;
  const category: Category = aspect < 0.75 ? 'shoes' : aspect >= 1.6 ? 'bottoms' : 'tops';
  return { category, confidence: 0.15 };
}
