import { useEffect, useMemo, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { useLiveQuery } from 'dexie-react-hooks';
import { db, type ClothingItem } from '../db';
import { CATEGORIES, CATEGORY_INFO, type Category } from '../lib/categories';
import { getSearchConfig } from '../lib/onlineSearch';
import { Chip, EmptyState, ItemTile, PageHeader } from '../components/ui';
import { AddItemsModal, type PendingBatch } from './AddItems';
import { OnlineSearchModal } from './OnlineSearch';

export function WardrobePage() {
  const items = useLiveQuery(() => db.items.orderBy('createdAt').reverse().toArray(), []);
  const [category, setCategory] = useState<Category | null>(null);
  const [query, setQuery] = useState('');
  const [favoritesOnly, setFavoritesOnly] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [pending, setPending] = useState<PendingBatch | null>(null);
  const [showSearch, setShowSearch] = useState(false);
  const [searchEnabled, setSearchEnabled] = useState(false);
  const cameraInput = useRef<HTMLInputElement>(null);
  const libraryInput = useRef<HTMLInputElement>(null);

  useEffect(() => {
    getSearchConfig().then((c) => setSearchEnabled(c.search));
  }, []);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return (items ?? []).filter((item) => {
      if (category && item.category !== category) return false;
      if (favoritesOnly && !item.favorite) return false;
      if (!q) return true;
      return [item.name, item.colorName, item.brand, item.notes, CATEGORY_INFO[item.category].label]
        .join(' ')
        .toLowerCase()
        .includes(q);
    });
  }, [items, category, query, favoritesOnly]);

  const counts = useMemo(() => {
    const map = new Map<Category, number>();
    for (const item of items ?? []) map.set(item.category, (map.get(item.category) ?? 0) + 1);
    return map;
  }, [items]);

  const onFiles = (files: FileList | null) => {
    const list = Array.from(files ?? []).filter((f) => f.type.startsWith('image/') || f.name.match(/\.(heic|heif)$/i));
    if (list.length) setPending({ photos: list.slice(0, 20) });
    if (cameraInput.current) cameraInput.current.value = '';
    if (libraryInput.current) libraryInput.current.value = '';
  };

  const addButtons = (
    <>
      <button type="button" className="button primary" onClick={() => cameraInput.current?.click()}>
        📷 Take Photo
      </button>
      <button type="button" className="button" onClick={() => libraryInput.current?.click()}>
        🖼️ Upload Photos
      </button>
      {searchEnabled && (
        <button type="button" className="button" onClick={() => setShowSearch(true)}>
          🔎 Find Online by Brand
        </button>
      )}
    </>
  );

  return (
    <div className="page">
      <PageHeader
        title="Wardrobe"
        leading={
          <button
            type="button"
            className={`icon-button${favoritesOnly ? ' active' : ''}`}
            onClick={() => setFavoritesOnly((v) => !v)}
            aria-pressed={favoritesOnly}
            aria-label="Show favourites only"
          >
            {favoritesOnly ? '♥' : '♡'}
          </button>
        }
        trailing={
          <div className="menu-anchor">
            <button type="button" className="icon-button" onClick={() => setMenuOpen((v) => !v)} aria-label="Add clothes" aria-expanded={menuOpen}>
              ＋
            </button>
            {menuOpen && (
              <div className="menu" onClick={() => setMenuOpen(false)}>
                {addButtons}
              </div>
            )}
          </div>
        }
      />

      <input ref={cameraInput} type="file" accept="image/*" capture="environment" hidden onChange={(e) => onFiles(e.target.files)} />
      <input ref={libraryInput} type="file" accept="image/*" multiple hidden onChange={(e) => onFiles(e.target.files)} />

      {items === undefined ? null : items.length === 0 ? (
        <EmptyState icon="🧺" title="Your wardrobe is empty">
          <p>Photograph your clothes{searchEnabled ? ' or find them online by brand' : ''}. Rackd removes the background and sorts each item into a category for you.</p>
          <div className="stack-buttons">{addButtons}</div>
        </EmptyState>
      ) : (
        <>
          <input
            className="search-field"
            type="search"
            placeholder="Search name, colour, brand"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
          <div className="chip-row">
            <Chip label="All" count={items.length} selected={category === null} onClick={() => setCategory(null)} />
            {CATEGORIES.filter((c) => counts.get(c)).map((c) => (
              <Chip
                key={c}
                label={CATEGORY_INFO[c].label}
                icon={CATEGORY_INFO[c].icon}
                count={counts.get(c)}
                selected={category === c}
                onClick={() => setCategory(category === c ? null : c)}
              />
            ))}
          </div>

          {filtered.length === 0 ? (
            <p className="muted center">No matching items.</p>
          ) : category ? (
            <ItemGrid items={filtered} />
          ) : (
            CATEGORIES.map((c) => {
              const group = filtered.filter((i) => i.category === c);
              if (!group.length) return null;
              return (
                <section key={c} className="category-section">
                  <button type="button" className="section-title" onClick={() => setCategory(c)}>
                    <span>
                      {CATEGORY_INFO[c].icon} {CATEGORY_INFO[c].label} <span className="muted">{group.length}</span>
                    </span>
                    <span className="chevron" aria-hidden>›</span>
                  </button>
                  <ItemGrid items={group} />
                </section>
              );
            })
          )}
        </>
      )}

      {pending && <AddItemsModal batch={pending} onClose={() => setPending(null)} />}
      {showSearch && (
        <OnlineSearchModal
          onClose={() => setShowSearch(false)}
          onPick={(pick) => {
            setShowSearch(false);
            setPending({ photos: [pick.image], brand: pick.brand, typeHint: pick.type });
          }}
        />
      )}
    </div>
  );
}

function ItemGrid({ items }: { items: ClothingItem[] }) {
  return (
    <div className="item-grid">
      {items.map((item) => (
        <Link key={item.id} to={`/item/${item.id}`} className="plain-link">
          <ItemTile item={item} />
        </Link>
      ))}
    </div>
  );
}
