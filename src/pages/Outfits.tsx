import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { useLiveQuery } from 'dexie-react-hooks';
import { addPlan, db, deleteOutfit, type ClothingItem, type Outfit } from '../db';
import { formatDay, todayKey, useItemsMap } from '../lib/misc';
import { EmptyState, ItemTile, OutfitPreview, PageHeader } from '../components/ui';

export function OutfitsPage() {
  const outfits = useLiveQuery(() => db.outfits.orderBy('createdAt').reverse().toArray(), []);
  const plans = useLiveQuery(() => db.plans.toArray(), []);
  const items = useItemsMap();
  const navigate = useNavigate();

  if (!outfits || !items || !plans) return null;
  const today = todayKey();

  return (
    <div className="page">
      <PageHeader
        title="Outfits"
        trailing={
          <button type="button" className="icon-button" aria-label="New outfit" disabled={items.size === 0} onClick={() => navigate('/outfits/new')}>
            ＋
          </button>
        }
      />
      {outfits.length === 0 ? (
        <EmptyState icon="🪄" title="No outfits yet">
          <p>{items.size === 0 ? 'Add some clothes to your wardrobe, then mix and match them here.' : 'Mix and match your clothes into outfits.'}</p>
          {items.size > 0 && (
            <button type="button" className="button primary" onClick={() => navigate('/outfits/new')}>
              Build an Outfit
            </button>
          )}
        </EmptyState>
      ) : (
        <div className="outfit-grid">
          {outfits.map((o) => {
            const next = plans.filter((p) => p.outfitId === o.id && p.date >= today).map((p) => p.date).sort()[0];
            return (
              <Link key={o.id} to={`/outfits/${o.id}`} className="plain-link">
                <OutfitCard outfit={o} items={items} nextDate={next} />
              </Link>
            );
          })}
        </div>
      )}
    </div>
  );
}

export function OutfitCard({ outfit, items, nextDate }: { outfit: Outfit; items: Map<string, ClothingItem>; nextDate?: string }) {
  const count = outfit.placements.filter((p) => items.has(p.itemId)).length;
  return (
    <div className="outfit-card">
      <OutfitPreview outfit={outfit} items={items} className="card-canvas" />
      <div className="bold ellipsis">{outfit.name || 'Untitled Outfit'}</div>
      <div className="muted small">
        {count} item{count === 1 ? '' : 's'}
        {nextDate && <> · 📅 {formatDay(nextDate, { month: 'short', day: 'numeric' })}</>}
      </div>
    </div>
  );
}

export function OutfitDetailPage() {
  const { id = '' } = useParams();
  const navigate = useNavigate();
  const outfit = useLiveQuery(async () => (await db.outfits.get(id)) ?? null, [id]);
  const plans = useLiveQuery(() => db.plans.where('outfitId').equals(id).reverse().sortBy('date'), [id]);
  const items = useItemsMap();
  const [planDate, setPlanDate] = useState(todayKey());

  if (outfit === undefined || !items || !plans) return null;
  if (outfit === null) {
    return (
      <div className="page">
        <PageHeader title="Not found" leading={<Link to="/outfits" className="text-button">‹ Outfits</Link>} />
      </div>
    );
  }

  const today = todayKey();
  const worn = plans.filter((p) => p.date <= today).length;
  const outfitItems = [...outfit.placements].sort((a, b) => a.z - b.z).map((p) => items.get(p.itemId)).filter(Boolean) as ClothingItem[];

  const remove = async () => {
    if (!confirm('Delete this outfit? Your clothes stay in your wardrobe; calendar entries for this outfit are removed.')) return;
    await deleteOutfit(outfit.id);
    navigate('/outfits', { replace: true });
  };

  return (
    <div className="page">
      <PageHeader
        title={outfit.name || 'Untitled Outfit'}
        leading={<button type="button" className="text-button" onClick={() => navigate(-1)}>‹ Back</button>}
        trailing={<Link to={`/outfits/${outfit.id}/edit`} className="text-button">Edit</Link>}
      />

      <div className="detail-canvas">
        <OutfitPreview outfit={outfit} items={items} />
      </div>

      <section className="card form">
        <label>
          <span>Name</span>
          <input className="input" value={outfit.name} placeholder="Outfit name" onChange={(e) => db.outfits.update(outfit.id, { name: e.target.value })} />
        </label>
      </section>

      <section className="card">
        <h3>Items</h3>
        <div className="h-scroll">
          {outfitItems.map((item) => (
            <Link key={item.id} to={`/item/${item.id}`} className="plain-link mini-item">
              <ItemTile item={item} />
            </Link>
          ))}
        </div>
      </section>

      <section className="card">
        <h3>Calendar</h3>
        <div className="row-gap">
          <input type="date" className="input" value={planDate} onChange={(e) => setPlanDate(e.target.value)} aria-label="Date" />
          <button type="button" className="button primary" disabled={!planDate} onClick={() => addPlan(planDate, outfit.id)}>
            📅 Plan
          </button>
        </div>
        {plans.length > 0 && (
          <>
            <ul className="plan-list">
              {plans.map((p) => (
                <li key={p.id}>
                  <span>{p.date <= today ? '✅' : '🕒'} {formatDay(p.date, { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' })}</span>
                  <button type="button" className="icon-button small" aria-label="Remove date" onClick={() => db.plans.delete(p.id)}>
                    ✕
                  </button>
                </li>
              ))}
            </ul>
            <p className="muted small">Worn {worn} time{worn === 1 ? '' : 's'}.</p>
          </>
        )}
      </section>

      <section className="card actions">
        <button type="button" className="button danger" onClick={remove}>
          🗑️ Delete outfit
        </button>
      </section>
    </div>
  );
}
