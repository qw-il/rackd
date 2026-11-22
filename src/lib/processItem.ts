import { removeBackground, type RemovalMethod } from './backgroundRemoval';
import { CATEGORY_INFO, categoryFromText, type Category } from './categories';
import { classifyClothing } from './classifier';
import { dominantColor } from './color';
import { blobToCanvas, canvasToBlob } from './imageUtils';

export interface ProcessedItem {
  /** Downscaled original photo (JPEG). */
  original: Blob;
  /** Background-removed PNG, or null if removal failed. */
  cutout: Blob | null;
  removalMethod: RemovalMethod | null;
  removalNote?: string;
  category: Category;
  confidence: number;
  colorName: string;
  colorHex: string;
  suggestedName: string;
}

export interface ProcessHints {
  /** What the user typed, e.g. "black 501 jeans" – beats the model's guess. */
  typeHint?: string;
}

/** Photo → background removed → categorised → colour detected. */
export async function processPhoto(
  photo: Blob,
  hints: ProcessHints = {},
  onStatus?: (message: string) => void,
): Promise<ProcessedItem> {
  onStatus?.('Preparing photo…');
  const canvas = await blobToCanvas(photo);
  const original = await canvasToBlob(canvas, 'image/jpeg', 0.88);

  let cutoutCanvas: HTMLCanvasElement | null = null;
  let removalMethod: RemovalMethod | null = null;
  let removalNote: string | undefined;
  try {
    const result = await removeBackground(canvas, onStatus);
    cutoutCanvas = result.canvas;
    removalMethod = result.method;
  } catch (error) {
    removalNote = error instanceof Error ? error.message : String(error);
  }

  const subject = cutoutCanvas ?? canvas;
  const hinted = hints.typeHint ? categoryFromText(hints.typeHint) : null;
  const classification = hinted
    ? { category: hinted, confidence: 1, label: undefined }
    : await classifyClothing(subject, onStatus);
  const color = dominantColor(subject);

  const typed = hints.typeHint?.trim();
  const noun = classification.label ?? CATEGORY_INFO[classification.category].singular;
  const suggestedName = typed
    ? typed[0].toUpperCase() + typed.slice(1)
    : [color?.name, noun].filter(Boolean).join(' ');

  return {
    original,
    cutout: cutoutCanvas ? await canvasToBlob(cutoutCanvas, 'image/png') : null,
    removalMethod,
    removalNote,
    category: classification.category,
    confidence: classification.confidence,
    colorName: color?.name ?? '',
    colorHex: color?.hex ?? '',
    suggestedName,
  };
}

/** Re-runs background removal on a stored original photo. */
export async function redoBackgroundRemoval(original: Blob): Promise<Blob> {
  const canvas = await blobToCanvas(original);
  const { canvas: cutout } = await removeBackground(canvas);
  return canvasToBlob(cutout, 'image/png');
}
