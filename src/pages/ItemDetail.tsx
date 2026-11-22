import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { useLiveQuery } from 'dexie-react-hooks';
import { db, deleteItem, type ClothingItem } from '../db';
import { CATEGORIES, CATEGORY_INFO, type Category } from '../lib/categories';
import { formatDay, todayKey, useItemsMap } from '../lib/misc';
import { redoBackgroundRemoval } from '../lib/processItem';
import { ColorSwatch, ItemImage, OutfitPreview, PageHeader } from '../components/ui';

export function ItemDetailPage() {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const item = useLiveQuery(async () => (await db.items.get(id)) ?? null, [id]);
  const outfits = useLiveQuery(() => db.outfits.where('itemIds').equals(id).toArray(), [id]);
  const wornDates = useLiveQuery(async () => {
    const outfitIds = (await db.outfits.where('itemIds').equals(id).primaryKeys()) as string[];
    if (!outfitIds.length) return [];
    const plans = await db.plans.where('outfitId').anyOf(outfitIds).toArray();
    const today = todayKey();
    return [...new Set(plans.map((p) => p.date).filter((d) => d <= today))].sort();
  }, [id]);
  const itemsMap = useItemsMap();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (item === undefined) return null; // loading
  if (item === null) {
    return (
      <div className="page">
        <PageHeader title="Not found" leading={<Link to="/" className="text-button">‹ Wardrobe</Link>} />
      </div>
    );
  }

  const update = (patch: Partial<ClothingItem>) => db.items.update(item.id, patch);

  const redo = async () => {
    if (!item.original) return;
    setBusy(true);
    setError(null);
    try {
      update({ image: await redoBackgroundRemoval(item.original) });
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setBusy(false);
    }
  };

  const remove = async () => {
    if (!confirm('Delete this item? It will also be removed from any outfits.')) return;
    await deleteItem(item.id);
    navigate('/', { replace: true });
  };

  return (
    <div className="page">
      <PageHeader
        title={item.name || CATEGORY_INFO[item.category].singular}
        leading={<button type="button" className="text-button" onClick={() => navigate(-1)}>‹ Back</button>}
      />

      <div className="detail-image checkerboard">
        <ItemImage item={item} />
        {busy && <span className="spinner overlay" />}
      </div>

      <section className="card form">
        <label>
          <span>Name</span>
          <input className="input" value={item.name} onChange={(e) => update({ name: e.target.value })} />
        </label>
        <label>
          <span>Category</span>
          <select className="input" value={item.category} onChange={(e) => update({ category: e.target.value as Category })}>
            {CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {CATEGORY_INFO[c].icon} {CATEGORY_INFO[c].label}
              </option>
            ))}
          </select>
        </label>
        <label>
          <span>Colour</span>
          <span className="row-gap grow">
            <ColorSwatch hex={item.colorHex} />
            <input className="input" value={item.colorName} onChange={(e) => update({ colorName: e.target.value })} />
          </span>
        </label>
        <label>
          <span>Brand</span>
          <input className="input" value={item.brand} onChange={(e) => update({ brand: e.target.value })} />
        </label>
        <label className="toggle">
          <input type="checkbox" checked={item.favorite} onChange={(e) => update({ favorite: e.target.checked })} />
          ♥ Favourite
        </label>
        <label className="column">
          <span>Notes</span>
          <textarea
            className="input"
            rows={3}
            placeholder="Size, fit, care instructions…"
            value={item.notes}
            onChange={(e) => update({ notes: e.target.value })}
          />
        </label>
      </section>

      <section className="card">
        <h3>Wear history</h3>
        <dl className="stats">
          <dt>Times worn</dt>
          <dd>{wornDates?.length ?? 0}</dd>
          <dt>Last worn</dt>
          <dd>{wornDates?.length ? formatDay(wornDates[wornDates.length - 1], { month: 'short', day: 'numeric', year: 'numeric' }) : 'Never'}</dd>
          <dt>Added</dt>
          <dd>{new Date(item.createdAt).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })}</dd>
        </dl>
      </section>

      {outfits && outfits.length > 0 && itemsMap && (
        <section className="card">
          <h3>In {outfits.length} outfit{outfits.length === 1 ? '' : 's'}</h3>
          <div className="h-scroll">
            {outfits.map((o) => (
              <Link key={o.id} to={`/outfits/${o.id}`} className="mini-outfit plain-link">
                <OutfitPreview outfit={o} items={itemsMap} />
                <span className="small">{o.name || 'Untitled'}</span>
              </Link>
            ))}
          </div>
        </section>
      )}

      <section className="card actions">
        {error && <p className="warning">⚠️ {error}</p>}
        {item.original && (
          <>
            <button type="button" className="button" disabled={busy} onClick={redo}>
              ✨ Redo background removal
            </button>
            <button type="button" className="button" disabled={busy} onClick={() => update({ image: item.original! })}>
              🖼️ Use original photo
            </button>
          </>
        )}
        <button type="button" className="button danger" onClick={remove}>
          🗑️ Delete item
        </button>
      </section>
    </div>
  );
}
