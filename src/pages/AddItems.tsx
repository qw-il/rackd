import { useEffect, useRef, useState } from 'react';
import { db, newId } from '../db';
import { CATEGORIES, CATEGORY_INFO, type Category } from '../lib/categories';
import { useObjectUrl } from '../lib/misc';
import { processPhoto, type ProcessedItem } from '../lib/processItem';
import { ColorSwatch, Modal } from '../components/ui';

export interface PendingBatch {
  photos: Blob[];
  /** Pre-filled from an online search. */
  brand?: string;
  typeHint?: string;
}

interface Draft {
  key: string;
  processed: ProcessedItem;
  name: string;
  brand: string;
  category: Category;
  useCutout: boolean;
}

/** Processes each photo (background removal, category, colour), then lets the user review before saving. */
export function AddItemsModal({ batch, onClose }: { batch: PendingBatch; onClose: () => void }) {
  const [drafts, setDrafts] = useState<Draft[]>([]);
  const [status, setStatus] = useState('Starting…');
  const [processing, setProcessing] = useState(true);
  const [failures, setFailures] = useState<string[]>([]);
  const started = useRef(false);

  useEffect(() => {
    if (started.current) return; // React StrictMode runs effects twice in dev
    started.current = true;
    (async () => {
      for (const [index, photo] of batch.photos.entries()) {
        const prefix = batch.photos.length > 1 ? `Photo ${index + 1} of ${batch.photos.length}: ` : '';
        try {
          const processed = await processPhoto(photo, { typeHint: batch.typeHint }, (s) => setStatus(prefix + s));
          setDrafts((d) => [
            ...d,
            {
              key: newId(),
              processed,
              name: processed.suggestedName,
              brand: batch.brand ?? '',
              category: processed.category,
              useCutout: Boolean(processed.cutout),
            },
          ]);
        } catch (error) {
          setFailures((f) => [...f, `${prefix}${error instanceof Error ? error.message : String(error)}`]);
        }
      }
      setProcessing(false);
    })();
  }, [batch]);

  const update = (key: string, patch: Partial<Draft>) =>
    setDrafts((ds) => ds.map((d) => (d.key === key ? { ...d, ...patch } : d)));

  const save = async () => {
    const now = Date.now();
    await db.items.bulkAdd(
      drafts.map((d, i) => ({
        id: newId(),
        name: d.name.trim(),
        category: d.category,
        image: d.useCutout && d.processed.cutout ? d.processed.cutout : d.processed.original,
        original: d.processed.original,
        colorName: d.processed.colorName,
        colorHex: d.processed.colorHex,
        brand: d.brand.trim(),
        notes: '',
        favorite: false,
        createdAt: now + i,
      })),
    );
    onClose();
  };

  return (
    <Modal
      title={batch.photos.length === 1 ? 'New Item' : 'New Items'}
      onClose={onClose}
      closeDisabled={processing}
      actions={
        <button type="button" className="text-button bold" disabled={processing || drafts.length === 0} onClick={save}>
          {drafts.length > 1 ? 'Save All' : 'Save'}
        </button>
      }
    >
      {processing && (
        <div className="processing-banner" role="status">
          <span className="spinner" aria-hidden />
          <div>
            <div>{status}</div>
            <div className="muted small">Removing backgrounds and sorting into categories</div>
          </div>
        </div>
      )}
      {failures.map((f) => (
        <p key={f} className="warning">⚠️ {f}</p>
      ))}
      <ul className="draft-list">
        {drafts.map((draft) => (
          <DraftRow
            key={draft.key}
            draft={draft}
            onChange={(patch) => update(draft.key, patch)}
            onRemove={() => setDrafts((ds) => ds.filter((d) => d.key !== draft.key))}
          />
        ))}
      </ul>
      {!processing && drafts.length > 0 && <p className="muted small">Categories were detected automatically. Change any that are wrong.</p>}
    </Modal>
  );
}

function DraftRow({ draft, onChange, onRemove }: { draft: Draft; onChange: (patch: Partial<Draft>) => void; onRemove: () => void }) {
  const { processed } = draft;
  const imageUrl = useObjectUrl(draft.useCutout && processed.cutout ? processed.cutout : processed.original);
  const autoText =
    draft.category !== processed.category
      ? ''
      : processed.confidence >= 0.6
        ? 'Auto-sorted'
        : processed.confidence >= 0.3
          ? 'Best guess'
          : 'Please check category';

  return (
    <li className="draft-row">
      <div className="draft-image checkerboard">{imageUrl && <img src={imageUrl} alt="" />}</div>
      <div className="draft-fields">
        <input className="input bold" value={draft.name} placeholder="Name" aria-label="Name" onChange={(e) => onChange({ name: e.target.value })} />
        <input className="input" value={draft.brand} placeholder="Brand" aria-label="Brand" onChange={(e) => onChange({ brand: e.target.value })} />
        <select className="input" value={draft.category} aria-label="Category" onChange={(e) => onChange({ category: e.target.value as Category })}>
          {CATEGORIES.map((c) => (
            <option key={c} value={c}>
              {CATEGORY_INFO[c].icon} {CATEGORY_INFO[c].label}
            </option>
          ))}
        </select>
        <div className="muted small row-gap">
          <ColorSwatch hex={processed.colorHex} size={12} /> {processed.colorName}
          {autoText && <span>· {autoText}</span>}
        </div>
        {processed.cutout ? (
          <label className="toggle small">
            <input type="checkbox" checked={draft.useCutout} onChange={(e) => onChange({ useCutout: e.target.checked })} />
            Remove background
          </label>
        ) : (
          <p className="warning small">⚠️ {processed.removalNote ?? 'Couldn\'t find the item\'s edges – keeping the full photo.'}</p>
        )}
      </div>
      <button type="button" className="icon-button small" onClick={onRemove} aria-label="Remove from batch">
        ✕
      </button>
    </li>
  );
}
