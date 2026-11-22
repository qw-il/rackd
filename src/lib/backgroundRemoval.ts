import { blobToCanvas, canvasToBlob, cropToContent, opaqueFraction, cleanupMask } from './imageUtils';
import { removePlainBackground } from './plainBackground';

export type RemovalMethod = 'ai' | 'plain';

export interface RemovalResult {
  canvas: HTMLCanvasElement;
  method: RemovalMethod;
}

/** Model files are served by this app (copied in by scripts/copy-imgly-assets.mjs). */
const PUBLIC_PATH = new URL(`${import.meta.env.BASE_URL}imgly/`, window.location.href).toString();

let modelReady = false;

/**
 * Removes the background behind a clothing item.
 *
 * 1. An AI segmentation model running in the browser (any background).
 * 2. If that fails, a plain-background flood fill (walls, floors, product shots).
 */
export async function removeBackground(
  source: HTMLCanvasElement,
  onStatus?: (message: string) => void,
): Promise<RemovalResult> {
  let aiError: unknown;
  try {
    const { removeBackground: imglyRemove } = await import('@imgly/background-removal');
    const input = await canvasToBlob(source, 'image/png');
    if (!modelReady) onStatus?.('Loading background-removal model (first time only)…');
    const output = await imglyRemove(input, {
      publicPath: PUBLIC_PATH,
      model: 'small',
      output: { format: 'image/png' },
      progress: (key, current, total) => {
        if (key.startsWith('fetch') && total > 0) {
          onStatus?.(`Downloading model… ${Math.round((current / total) * 100)}%`);
        }
      },
    });
    modelReady = true;
    onStatus?.('Removing background…');
    const canvas = await blobToCanvas(output, Number.MAX_SAFE_INTEGER);
    cleanupMask(canvas);
    const coverage = opaqueFraction(canvas);
    const cropped = coverage > 0.02 ? cropToContent(canvas) : null;
    if (!cropped) throw new Error('No item found in the photo.');
    return { canvas: cropped, method: 'ai' };
  } catch (error) {
    aiError = error;
    console.warn('[rackd] AI background removal failed, trying plain-background method:', error);
  }

  const plain = removePlainBackground(source);
  const cropped = plain && cropToContent(plain);
  if (cropped) return { canvas: cropped, method: 'plain' };

  const reason = aiError instanceof Error ? aiError.message : String(aiError);
  throw new Error(
    `Couldn't separate the item from the background (${reason}). ` +
      'Try a photo of the whole item on a plain, contrasting background.',
  );
}
