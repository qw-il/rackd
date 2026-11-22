import { useEffect, type ReactNode } from 'react';
import type { ClothingItem, Outfit, Placement } from '../db';
import { CATEGORY_INFO } from '../lib/categories';
import { useObjectUrl } from '../lib/misc';

export function ItemImage({ item, className }: { item: ClothingItem; className?: string }) {
  const url = useObjectUrl(item.image);
  return url ? (
    <img className={className} src={url} alt={item.name || CATEGORY_INFO[item.category].singular} draggable={false} />
  ) : (
    <span className={`${className ?? ''} placeholder-icon`} aria-hidden>
      {CATEGORY_INFO[item.category].icon}
    </span>
  );
}

export function ItemTile({ item, showName = true, selected = false }: { item: ClothingItem; showName?: boolean; selected?: boolean }) {
  return (
    <div className={`item-tile${selected ? ' selected' : ''}`}>
      <div className="item-tile-image">
        <ItemImage item={item} />
        {item.favorite && <span className="tile-heart" aria-label="Favourite">♥</span>}
        {selected && <span className="tile-check" aria-label="In outfit">✓</span>}
      </div>
      {showName && <div className="item-tile-name">{item.name || CATEGORY_INFO[item.category].singular}</div>}
    </div>
  );
}

export function Chip({
  label,
  icon,
  count,
  selected,
  onClick,
}: {
  label: string;
  icon?: string;
  count?: number;
  selected: boolean;
  onClick: () => void;
}) {
  return (
    <button type="button" className={`chip${selected ? ' selected' : ''}`} onClick={onClick} aria-pressed={selected}>
      {icon && <span aria-hidden>{icon}</span>}
      {label}
      {count !== undefined && <span className="chip-count">{count}</span>}
    </button>
  );
}

export function ColorSwatch({ hex, size = 14 }: { hex: string; size?: number }) {
  if (!hex) return null;
  return <span className="swatch" style={{ background: hex, width: size, height: size }} aria-hidden />;
}

/** Renders placements on a 3:4 canvas. */
export function OutfitCanvasView({
  placements,
  items,
  className,
}: {
  placements: Placement[];
  items: Map<string, ClothingItem>;
  className?: string;
}) {
  return (
    <div className={`outfit-canvas ${className ?? ''}`}>
      {placements
        .filter((p) => items.has(p.itemId))
        .sort((a, b) => a.z - b.z)
        .map((p) => (
          <div
            key={p.itemId}
            className="canvas-item"
            style={{ left: `${p.x * 100}%`, top: `${p.y * 100}%`, width: `${p.scale * 100}%`, zIndex: p.z }}
          >
            <ItemImage item={items.get(p.itemId)!} />
          </div>
        ))}
    </div>
  );
}

export function OutfitPreview({ outfit, items, className }: { outfit: Outfit; items: Map<string, ClothingItem>; className?: string }) {
  return <OutfitCanvasView placements={outfit.placements} items={items} className={className} />;
}

export function Modal({
  title,
  onClose,
  actions,
  children,
  closeLabel = 'Cancel',
  closeDisabled = false,
}: {
  title: string;
  onClose: () => void;
  actions?: ReactNode;
  children: ReactNode;
  closeLabel?: string;
  closeDisabled?: boolean;
}) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !closeDisabled) onClose();
    };
    window.addEventListener('keydown', onKey);
    document.body.classList.add('modal-open');
    return () => {
      window.removeEventListener('keydown', onKey);
      document.body.classList.remove('modal-open');
    };
  }, [onClose, closeDisabled]);

  return (
    <div className="modal-backdrop" onClick={() => !closeDisabled && onClose()}>
      <div className="modal" role="dialog" aria-modal="true" aria-label={title} onClick={(e) => e.stopPropagation()}>
        <header className="modal-header">
          <button type="button" className="text-button" onClick={onClose} disabled={closeDisabled}>
            {closeLabel}
          </button>
          <h2>{title}</h2>
          <div className="modal-actions">{actions}</div>
        </header>
        <div className="modal-body">{children}</div>
      </div>
    </div>
  );
}

export function PageHeader({ title, leading, trailing }: { title: string; leading?: ReactNode; trailing?: ReactNode }) {
  return (
    <header className="page-header">
      <div className="page-header-side">{leading}</div>
      <h1>{title}</h1>
      <div className="page-header-side trailing">{trailing}</div>
    </header>
  );
}

export function EmptyState({ icon, title, children }: { icon: string; title: string; children?: ReactNode }) {
  return (
    <div className="empty-state">
      <div className="empty-icon" aria-hidden>
        {icon}
      </div>
      <h2>{title}</h2>
      {children}
    </div>
  );
}
