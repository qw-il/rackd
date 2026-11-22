import Dexie, { type EntityTable } from 'dexie';
import type { Category } from './lib/categories';

export interface ClothingItem {
  id: string;
  name: string;
  category: Category;
  /** PNG with the background removed (or the original photo if removal failed). */
  image: Blob;
  /** The photo as taken, kept so background removal can be re-run. */
  original?: Blob;
  colorName: string;
  colorHex: string;
  brand: string;
  notes: string;
  favorite: boolean;
  createdAt: number;
}

/** Where an item sits on the outfit canvas, in 0…1 coordinates. */
export interface Placement {
  itemId: string;
  x: number;
  y: number;
  /** Item width as a fraction of the canvas width. */
  scale: number;
  z: number;
}

export interface Outfit {
  id: string;
  name: string;
  notes: string;
  createdAt: number;
  placements: Placement[];
  /** Denormalised from placements so we can index "outfits containing item X". */
  itemIds: string[];
}

/** An outfit planned (or logged as worn) on a calendar day. */
export interface Plan {
  id: string;
  /** Local calendar day, `YYYY-MM-DD`. */
  date: string;
  outfitId: string;
  createdAt: number;
}

class RackdDB extends Dexie {
  items!: EntityTable<ClothingItem, 'id'>;
  outfits!: EntityTable<Outfit, 'id'>;
  plans!: EntityTable<Plan, 'id'>;

  constructor() {
    super('rackd');
    this.version(1).stores({
      items: 'id, category, createdAt',
      outfits: 'id, createdAt, *itemIds',
      plans: 'id, date, outfitId',
    });
  }
}

export const db = new RackdDB();

export const newId = () => crypto.randomUUID();

export async function saveOutfit(outfit: Omit<Outfit, 'itemIds'>): Promise<string> {
  const itemIds = [...new Set(outfit.placements.map((p) => p.itemId))];
  await db.outfits.put({ ...outfit, itemIds });
  return outfit.id;
}

/** Deletes an item and removes it from any outfits that use it. */
export async function deleteItem(id: string) {
  await db.transaction('rw', db.items, db.outfits, async () => {
    const outfits = await db.outfits.where('itemIds').equals(id).toArray();
    for (const outfit of outfits) {
      const placements = outfit.placements.filter((p) => p.itemId !== id);
      await db.outfits.put({ ...outfit, placements, itemIds: placements.map((p) => p.itemId) });
    }
    await db.items.delete(id);
  });
}

/** Deletes an outfit and its calendar entries. Clothes are kept. */
export async function deleteOutfit(id: string) {
  await db.transaction('rw', db.outfits, db.plans, async () => {
    await db.plans.where('outfitId').equals(id).delete();
    await db.outfits.delete(id);
  });
}

export async function addPlan(date: string, outfitId: string) {
  await db.plans.add({ id: newId(), date, outfitId, createdAt: Date.now() });
}
