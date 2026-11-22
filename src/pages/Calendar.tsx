import { useMemo, useRef, useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { useLiveQuery } from 'dexie-react-hooks';
import { addPlan, db, type Plan } from '../db';
import { dayKey, formatDay, parseDayKey, todayKey, useItemsMap } from '../lib/misc';
import { Modal, OutfitPreview, PageHeader } from '../components/ui';
import { OutfitCard } from './Outfits';

const startOfMonth = (d: Date) => new Date(d.getFullYear(), d.getMonth(), 1);

export function CalendarPage() {
  const location = useLocation();
  const initial = (location.state as { date?: string } | null)?.date ?? todayKey();
  const [selected, setSelected] = useState(initial);
  const [month, setMonth] = useState(() => startOfMonth(parseDayKey(initial)));
  const [showPicker, setShowPicker] = useState(false);
  const plans = useLiveQuery(() => db.plans.toArray(), []);
  const outfits = useLiveQuery(async () => new Map((await db.outfits.toArray()).map((o) => [o.id, o])), []);
  const items = useItemsMap();
  const navigate = useNavigate();
  const touchStart = useRef<number | null>(null);

  const byDay = useMemo(() => {
    const map = new Map<string, Plan[]>();
    for (const p of plans ?? []) {
      if (!outfits?.has(p.outfitId)) continue;
      map.set(p.date, [...(map.get(p.date) ?? []), p]);
    }
    for (const list of map.values()) list.sort((a, b) => a.createdAt - b.createdAt);
    return map;
  }, [plans, outfits]);

  const days = useMemo(() => {
    const first = startOfMonth(month);
    const daysInMonth = new Date(first.getFullYear(), first.getMonth() + 1, 0).getDate();
    // Monday-first weeks in most locales; Sunday-first in en-US.
    const sundayFirst = new Intl.Locale(navigator.language).region === 'US';
    const leading = (first.getDay() - (sundayFirst ? 0 : 1) + 7) % 7;
    const cells: (string | null)[] = Array(leading).fill(null);
    for (let d = 1; d <= daysInMonth; d++) cells.push(dayKey(new Date(first.getFullYear(), first.getMonth(), d)));
    return { cells, sundayFirst };
  }, [month]);

  const weekdays = useMemo(() => {
    const base = new Date(2024, 0, days.sundayFirst ? 7 : 1); // a Sunday / a Monday
    return Array.from({ length: 7 }, (_, i) =>
      new Date(base.getFullYear(), base.getMonth(), base.getDate() + i).toLocaleDateString(undefined, { weekday: 'narrow' }),
    );
  }, [days.sundayFirst]);

  if (!plans || !outfits || !items) return null;

  const shift = (delta: number) => setMonth((m) => new Date(m.getFullYear(), m.getMonth() + delta, 1));
  const today = todayKey();
  const selectedPlans = byDay.get(selected) ?? [];

  return (
    <div className="page">
      <PageHeader
        title="Outfit Calendar"
        trailing={
          <button
            type="button"
            className="text-button"
            onClick={() => {
              setSelected(today);
              setMonth(startOfMonth(new Date()));
            }}
          >
            Today
          </button>
        }
      />

      <section
        className="month"
        onTouchStart={(e) => (touchStart.current = e.touches[0].clientX)}
        onTouchEnd={(e) => {
          if (touchStart.current === null) return;
          const dx = e.changedTouches[0].clientX - touchStart.current;
          if (Math.abs(dx) > 60) shift(dx < 0 ? 1 : -1);
          touchStart.current = null;
        }}
      >
        <div className="month-header">
          <h2>{month.toLocaleDateString(undefined, { month: 'long', year: 'numeric' })}</h2>
          <div>
            <button type="button" className="icon-button" aria-label="Previous month" onClick={() => shift(-1)}>‹</button>
            <button type="button" className="icon-button" aria-label="Next month" onClick={() => shift(1)}>›</button>
          </div>
        </div>
        <div className="weekdays">
          {weekdays.map((w, i) => (
            <span key={i}>{w}</span>
          ))}
        </div>
        <div className="days">
          {days.cells.map((key, i) => {
            if (!key) return <span key={`blank-${i}`} />;
            const dayPlans = byDay.get(key) ?? [];
            const outfit = dayPlans[0] && outfits.get(dayPlans[0].outfitId);
            return (
              <button
                key={key}
                type="button"
                className={`day${key === selected ? ' selected' : ''}${key === today ? ' today' : ''}`}
                onClick={() => setSelected(key)}
                aria-label={formatDay(key) + (dayPlans.length ? `, ${dayPlans.length} outfit${dayPlans.length > 1 ? 's' : ''}` : '')}
              >
                <span className="day-number">{parseDayKey(key).getDate()}</span>
                <span className="day-thumb">{outfit && <OutfitPreview outfit={outfit} items={items} />}</span>
                {dayPlans.length > 1 && <span className="day-extra">+{dayPlans.length - 1}</span>}
              </button>
            );
          })}
        </div>
      </section>

      <section className="day-detail">
        <div className="day-detail-header">
          <div>
            <div className="muted small upper">{formatDay(selected, { weekday: 'long' })}</div>
            <h2>{formatDay(selected, { month: 'long', day: 'numeric' })}</h2>
          </div>
          <button type="button" className="button primary pill" onClick={() => setShowPicker(true)}>
            ＋ Add Outfit
          </button>
        </div>
        {selectedPlans.length === 0 ? (
          <p className="card muted">{selected < today ? 'Nothing logged for this day.' : 'Nothing planned yet. Add an outfit to plan what you\'ll wear.'}</p>
        ) : (
          selectedPlans.map((plan) => {
            const outfit = outfits.get(plan.outfitId)!;
            const names = outfit.placements.map((p) => items.get(p.itemId)?.name).filter(Boolean).join(', ');
            return (
              <div key={plan.id} className="card planned-row">
                <Link to={`/outfits/${outfit.id}`} className="plain-link planned-link">
                  <div className="planned-thumb">
                    <OutfitPreview outfit={outfit} items={items} />
                  </div>
                  <div>
                    <div className="bold">{outfit.name || 'Untitled Outfit'}</div>
                    <div className="muted small clamp-3">{names}</div>
                  </div>
                </Link>
                <button type="button" className="icon-button small" aria-label="Remove from day" onClick={() => db.plans.delete(plan.id)}>
                  ✕
                </button>
              </div>
            );
          })
        )}
      </section>

      {showPicker && (
        <Modal title={formatDay(selected, { weekday: 'short', month: 'short', day: 'numeric' })} onClose={() => setShowPicker(false)}>
          <button
            type="button"
            className="button wide"
            disabled={items.size === 0}
            onClick={() => navigate(`/outfits/new?date=${selected}`)}
          >
            ➕ Create a New Outfit
          </button>
          {outfits.size === 0 ? (
            <p className="muted center">
              {items.size === 0 ? 'Add clothes to your wardrobe first, then build outfits to plan.' : 'You haven\'t saved any outfits yet.'}
            </p>
          ) : (
            <div className="outfit-grid picker">
              {[...outfits.values()]
                .sort((a, b) => b.createdAt - a.createdAt)
                .map((o) => (
                  <button
                    key={o.id}
                    type="button"
                    className="plain-button"
                    onClick={async () => {
                      await addPlan(selected, o.id);
                      setShowPicker(false);
                    }}
                  >
                    <OutfitCard outfit={o} items={items} />
                  </button>
                ))}
            </div>
          )}
        </Modal>
      )}
    </div>
  );
}
