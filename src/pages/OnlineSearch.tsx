import { useState, type FormEvent } from 'react';
import { buildQuery, downloadResult, searchImages, type SearchResult } from '../lib/onlineSearch';
import { Modal } from '../components/ui';

export interface OnlinePick {
  image: Blob;
  brand: string;
  type: string;
}

/** Type a brand and item type, search the web for product photos, pick one. */
export function OnlineSearchModal({ onClose, onPick }: { onClose: () => void; onPick: (pick: OnlinePick) => void }) {
  const [brand, setBrand] = useState('');
  const [type, setType] = useState('');
  const [color, setColor] = useState('');
  const [productShots, setProductShots] = useState(true);
  const [results, setResults] = useState<SearchResult[] | null>(null);
  const [searching, setSearching] = useState(false);
  const [downloading, setDownloading] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);

  const canSearch = (brand + type).trim().length > 0 && !searching;

  const search = async (e?: FormEvent) => {
    e?.preventDefault();
    if (!canSearch) return;
    setSearching(true);
    setError(null);
    try {
      setResults(await searchImages(buildQuery(brand, type, color, productShots)));
    } catch (err) {
      setResults(null);
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setSearching(false);
    }
  };

  const pick = async (result: SearchResult, index: number) => {
    setDownloading(index);
    setError(null);
    try {
      const image = await downloadResult(result);
      onPick({
        image,
        brand: brand.trim(),
        type: [color, type].map((s) => s.trim()).filter(Boolean).join(' '),
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setDownloading(null);
    }
  };

  return (
    <Modal title="Find Online" onClose={onClose} closeDisabled={downloading !== null}>
      <form className="search-form" onSubmit={search}>
        <input className="input" autoFocus placeholder="Brand (e.g. Levi's)" value={brand} onChange={(e) => setBrand(e.target.value)} />
        <input className="input" placeholder="Type (e.g. 501 jeans)" value={type} onChange={(e) => setType(e.target.value)} />
        <input className="input" placeholder="Colour (optional)" value={color} onChange={(e) => setColor(e.target.value)} />
        <label className="toggle">
          <input type="checkbox" checked={productShots} onChange={(e) => setProductShots(e.target.checked)} />
          Prefer clean product shots
        </label>
        <button type="submit" className="button primary wide" disabled={!canSearch}>
          {searching ? 'Searching…' : '🔎 Search'}
        </button>
      </form>

      {error && <p className="warning">⚠️ {error}</p>}
      {results && results.length === 0 && <p className="muted center">No results. Try different words.</p>}
      {results && results.length > 0 && (
        <>
          <p className="muted small">Tap the photo that matches your item. Its background will be removed automatically.</p>
          <div className="result-grid">
            {results.map((r, i) => (
              <button
                key={`${r.thumbnail}-${i}`}
                type="button"
                className="result-tile"
                onClick={() => pick(r, i)}
                disabled={downloading !== null}
                title={r.title}
              >
                <img src={r.thumbnail} alt={r.title || 'Search result'} loading="lazy" referrerPolicy="no-referrer" />
                {downloading === i && (
                  <span className="result-overlay">
                    <span className="spinner light" />
                  </span>
                )}
              </button>
            ))}
          </div>
        </>
      )}
    </Modal>
  );
}
