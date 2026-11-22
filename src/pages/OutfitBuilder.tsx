import { useEffect, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent, type WheelEvent as ReactWheelEvent } from 'react';
import { useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { useLiveQuery } from 'dexie-react-hooks';
import { addPlan, db, newId, saveOutfit, type ClothingItem, type Placement } from '../db';
import { CATEGORIES, CATEGORY_INFO, type Category } from '../lib/categories';
import { formatDay } from '../lib/misc';
import { Chip, EmptyState, ItemImage, ItemTile, PageHeader } from '../components/ui';

/** Picking a new item in these categories swaps out the current one. */
const SINGLE_SLOT = new Set<Category>(['tops', 'bottoms', 'dresses', 'outerwear', 'shoes']);

function defaultPlacement(item: ClothingItem): Placement {
  const info = CATEGORY_INFO[item.category];
  return { itemId: item.id, x: info.x, y: info.y, scale: info.scale, z: info.z };
}

const clamp = (v: number, lo: number, hi: number) => Math.min(Math.max(v, lo), hi);

/**
 * Compose an outfit: tap clothes in the tray to add them, drag to move,
 * pinch (or scroll / use the slider) to resize.
 *   /outfits/new            – new outfit
 *   /outfits/new?date=…     – new outfit, then plan it on that day
 *   /outfits/:id/edit       – edit an existing outfit
 */
export function OutfitBuilderPage() {
  const { id } = useParams();
  const [params] = useSearchParams();
  const planDate = params.get('date');
  const navigate = useNavigate();

  const items = useLiveQuery(() => db.items.orderBy('createdAt').reverse().toArray(), []);
  const existing = useLiveQuery(async () => (id ? ((await db.outfits.get(id)) ?? null) : null), [id]);

  const [name, setName] = useState('');
  const [placements, setPlacements] = useState<Placement[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [tray, setTray] = useState<Category>('tops');
  const loaded = useRef(false);

  const itemsMap = useMemo(() => new Map((items ?? []).map((i) => [i.id, i])), [items]);
  const available = useMemo(() => CATEGORIES.filter((c) => items?.some((i) => i.category === c)), [items]);

  useEffect(() => {
    if (loaded.current || items === undefined || existing === undefined) return;
    loaded.current = true;
    if (existing) {
      setName(existing.name);
      setPlacements(existing.placements.filter((p) => itemsMap.has(p.itemId)));
    }
    if (available.length && !available.includes(tray)) setTray(available[0]);
  }, [items, existing, itemsMap, available, tray]);

  const toggle = (item: ClothingItem) => {
    setPlacements((current) => {
      if (current.some((p) => p.itemId === item.id)) {
        if (selected === item.id) setSelected(null);
        return current.filter((p) => p.itemId !== item.id);
      }
      let placement = defaultPlacement(item);
      let next = current;
      if (SINGLE_SLOT.has(item.category)) {
        const old = current.find((p) => itemsMap.get(p.itemId)?.category === item.category);
        if (old) {
          // Swap, keeping the old item's position and size.
          placement = { ...placement, x: old.x, y: old.y, scale: old.scale, z: old.z };
          next = current.filter((p) => p !== old);
        }
      }
      return [...next, placement];
    });
  };

  const shuffle = () => {
    const pick = (c: Category) => {
      const options = (items ?? []).filter((i) => i.category === c);
      return options[Math.floor(Math.random() * options.length)];
    };
    const picked: ClothingItem[] = [];
    const hasSeparates = pick('tops') && pick('bottoms');
    const dress = pick('dresses');
    if (dress && (!hasSeparates || Math.random() < 0.5)) picked.push(dress);
    else picked.push(...[pick('tops'), pick('bottoms')].filter(Boolean));
    const shoes = pick('shoes');
    if (shoes) picked.push(shoes);
    if (Math.random() < 0.4 && pick('outerwear')) picked.push(pick('outerwear'));
    if (Math.random() < 0.35 && pick('bags')) picked.push(pick('bags'));
    if (Math.random() < 0.35 && pick('accessories')) picked.push(pick('accessories'));
    if (!picked.length && items?.length) picked.push(items[Math.floor(Math.random() * items.length)]);
    setSelected(null);
    setPlacements(picked.map(defaultPlacement));
  };

  const updatePlacement = (itemId: string, patch: Partial<Placement>) =>
    setPlacements((ps) => ps.map((p) => (p.itemId === itemId ? { ...p, ...patch } : p)));

  const bringToFront = (itemId: string) => {
    setSelected(itemId);
    setPlacements((ps) => {
      const top = Math.max(0, ...ps.map((p) => p.z)) + 1;
      return ps.map((p) => (p.itemId === itemId ? { ...p, z: top } : p));
    });
  };

  const save = async () => {
    const outfitId = existing?.id ?? newId();
    await saveOutfit({
      id: outfitId,
      name: name.trim(),
      notes: existing?.notes ?? '',
      createdAt: existing?.createdAt ?? Date.now(),
      placements,
    });
    if (planDate) {
      await addPlan(planDate, outfitId);
      navigate('/calendar', { replace: true, state: { date: planDate } });
    } else {
      if (existing) navigate(-1);
      else navigate(`/outfits/${outfitId}`, { replace: true });
    }
  };

  if (items === undefined || existing === undefined) return null;
  const selectedPlacement = placements.find((p) => p.itemId === selected);

  return (
    <div className="page builder-page">
      <PageHeader
        title={existing ? 'Edit Outfit' : 'New Outfit'}
        leading={<button type="button" className="text-button" onClick={() => navigate(-1)}>Cancel</button>}
        trailing={
          <button type="button" className="text-button bold" disabled={!placements.length} onClick={save}>
            Save
          </button>
        }
      />
      {planDate && <p className="muted small center">Will be planned for {formatDay(planDate)}</p>}

      <input className="input title-input" placeholder="Outfit name" value={name} onChange={(e) => setName(e.target.value)} />

      <EditableCanvas
        placements={placements}
        items={itemsMap}
        selected={selected}
        onSelect={bringToFront}
        onDeselect={() => setSelected(null)}
        onChange={updatePlacement}
      />

      <div className="canvas-controls">
        <button type="button" className="button small" onClick={shuffle} disabled={!items.length}>
          🔀 Shuffle
        </button>
        {selectedPlacement ? (
          <>
            <label className="size-slider">
              <span className="sr-only">Size</span>
              <input
                type="range"
                min={0.08}
                max={1.2}
                step={0.01}
                value={selectedPlacement.scale}
                onChange={(e) => updatePlacement(selectedPlacement.itemId, { scale: Number(e.target.value) })}
                aria-label="Item size"
              />
            </label>
            <button
              type="button"
              className="icon-button small"
              aria-label="Reset position"
              onClick={() => {
                const item = itemsMap.get(selectedPlacement.itemId);
                if (item) updatePlacement(item.id, defaultPlacement(item));
              }}
            >
              ↺
            </button>
            <button
              type="button"
              className="icon-button small danger"
              aria-label="Remove from outfit"
              onClick={() => {
                setPlacements((ps) => ps.filter((p) => p.itemId !== selectedPlacement.itemId));
                setSelected(null);
              }}
            >
              🗑
            </button>
          </>
        ) : (
          placements.length > 0 && (
            <button type="button" className="text-button danger" onClick={() => setPlacements([])}>
              Clear
            </button>
          )
        )}
      </div>

      <div className="tray">
        {items.length === 0 ? (
          <EmptyState icon="🧺" title="No clothes yet">
            <p>Add items in the Wardrobe tab first.</p>
          </EmptyState>
        ) : (
          <>
            <div className="chip-row">
              {available.map((c) => (
                <Chip key={c} label={CATEGORY_INFO[c].label} icon={CATEGORY_INFO[c].icon} selected={tray === c} onClick={() => setTray(c)} />
              ))}
            </div>
            <div className="h-scroll tray-items">
              {items
                .filter((i) => i.category === tray)
                .map((item) => (
                  <button key={item.id} type="button" className="tray-button" onClick={() => toggle(item)}>
                    <ItemTile item={item} showName={false} selected={placements.some((p) => p.itemId === item.id)} />
                  </button>
                ))}
            </div>
          </>
        )}
      </div>
    </div>
  );
}

interface Gesture {
  itemId: string;
  start: Placement;
  startCentroid: { x: number; y: number };
  startDistance: number;
}

/** Canvas where items can be dragged (one finger / mouse) and pinched (two fingers). */
function EditableCanvas({
  placements,
  items,
  selected,
  onSelect,
  onDeselect,
  onChange,
}: {
  placements: Placement[];
  items: Map<string, ClothingItem>;
  selected: string | null;
  onSelect: (itemId: string) => void;
  onDeselect: () => void;
  onChange: (itemId: string, patch: Partial<Placement>) => void;
}) {
  const canvasRef = useRef<HTMLDivElement>(null);
  const pointers = useRef(new Map<number, { x: number; y: number }>());
  const gesture = useRef<Gesture | null>(null);
  const latest = useRef(placements);
  latest.current = placements;

  const centroid = () => {
    const pts = [...pointers.current.values()];
    return { x: pts.reduce((s, p) => s + p.x, 0) / pts.length, y: pts.reduce((s, p) => s + p.y, 0) / pts.length };
  };
  const distance = () => {
    const [a, b] = [...pointers.current.values()];
    return a && b ? Math.hypot(a.x - b.x, a.y - b.y) : 0;
  };
  /** (Re)start the gesture baseline, e.g. when a second finger lands. */
  const begin = (itemId: string) => {
    const start = latest.current.find((p) => p.itemId === itemId);
    gesture.current = start ? { itemId, start: { ...start }, startCentroid: centroid(), startDistance: distance() } : null;
  };

  const onPointerDown = (e: ReactPointerEvent, itemId: string) => {
    e.stopPropagation();
    e.preventDefault();
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (pointers.current.size === 1) onSelect(itemId);
    begin(gesture.current?.itemId ?? itemId);
  };

  const onPointerMove = (e: ReactPointerEvent) => {
    if (!pointers.current.has(e.pointerId) || !gesture.current || !canvasRef.current) return;
    pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
    const rect = canvasRef.current.getBoundingClientRect();
    const g = gesture.current;
    const c = centroid();
    const patch: Partial<Placement> = {
      x: clamp(g.start.x + (c.x - g.startCentroid.x) / rect.width, 0.02, 0.98),
      y: clamp(g.start.y + (c.y - g.startCentroid.y) / rect.height, 0.02, 0.98),
    };
    if (pointers.current.size >= 2 && g.startDistance > 0) {
      patch.scale = clamp((g.start.scale * distance()) / g.startDistance, 0.08, 1.2);
    }
    onChange(g.itemId, patch);
  };

  const onPointerUp = (e: ReactPointerEvent) => {
    pointers.current.delete(e.pointerId);
    if (pointers.current.size && gesture.current) begin(gesture.current.itemId);
    else gesture.current = null;
  };

  const onWheel = (e: ReactWheelEvent, itemId: string) => {
    const p = latest.current.find((pl) => pl.itemId === itemId);
    if (!p) return;
    onChange(itemId, { scale: clamp(p.scale * (e.deltaY < 0 ? 1.06 : 0.94), 0.08, 1.2) });
  };

  return (
    <div className="outfit-canvas editable" ref={canvasRef} onPointerDown={onDeselect}>
      {placements.length === 0 && (
        <div className="canvas-hint">
          <div aria-hidden>👆</div>
          Tap clothes below to add them.
          <br />
          Drag to move, pinch or scroll to resize.
        </div>
      )}
      {placements
        .filter((p) => items.has(p.itemId))
        .map((p) => (
          <div
            key={p.itemId}
            className={`canvas-item interactive${selected === p.itemId ? ' selected' : ''}`}
            style={{ left: `${p.x * 100}%`, top: `${p.y * 100}%`, width: `${p.scale * 100}%`, zIndex: p.z }}
            onPointerDown={(e) => onPointerDown(e, p.itemId)}
            onPointerMove={onPointerMove}
            onPointerUp={onPointerUp}
            onPointerCancel={onPointerUp}
            onWheel={(e) => onWheel(e, p.itemId)}
          >
            <ItemImage item={items.get(p.itemId)!} />
          </div>
        ))}
    </div>
  );
}
