import { useEffect, useState } from 'react';
import { useLiveQuery } from 'dexie-react-hooks';
import { db, type ClothingItem } from '../db';

/** An object URL for a Blob, revoked automatically. */
export function useObjectUrl(blob: Blob | null | undefined): string | undefined {
  const [url, setUrl] = useState<string>();
  useEffect(() => {
    if (!blob) {
      setUrl(undefined);
      return;
    }
    const next = URL.createObjectURL(blob);
    setUrl(next);
    return () => URL.revokeObjectURL(next);
  }, [blob]);
  return url;
}

/** All items keyed by id (live). */
export function useItemsMap(): Map<string, ClothingItem> | undefined {
  return useLiveQuery(async () => new Map((await db.items.toArray()).map((i) => [i.id, i])), []);
}

// MARK: Dates (local calendar days as YYYY-MM-DD)

export function dayKey(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

export function parseDayKey(key: string): Date {
  const [y, m, d] = key.split('-').map(Number);
  return new Date(y, m - 1, d);
}

export const todayKey = () => dayKey(new Date());

export function formatDay(key: string, options: Intl.DateTimeFormatOptions = { weekday: 'long', month: 'long', day: 'numeric' }) {
  return parseDayKey(key).toLocaleDateString(undefined, options);
}

export function displayName(item: Pick<ClothingItem, 'name' | 'category'>, singular: string) {
  return item.name.trim() || singular;
}
