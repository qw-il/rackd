export type Category = 'tops' | 'bottoms' | 'dresses' | 'outerwear' | 'shoes' | 'bags' | 'accessories';

export const CATEGORIES: Category[] = ['tops', 'bottoms', 'dresses', 'outerwear', 'shoes', 'bags', 'accessories'];

interface CategoryInfo {
  label: string;
  singular: string;
  icon: string;
  /** Default spot on the outfit canvas (0…1). */
  x: number;
  y: number;
  /** Default width as a fraction of the canvas. */
  scale: number;
  /** Stacking order: higher draws on top. */
  z: number;
}

export const CATEGORY_INFO: Record<Category, CategoryInfo> = {
  tops: { label: 'Tops', singular: 'Top', icon: '👕', x: 0.5, y: 0.27, scale: 0.44, z: 2 },
  bottoms: { label: 'Bottoms', singular: 'Bottoms', icon: '👖', x: 0.5, y: 0.62, scale: 0.4, z: 0 },
  dresses: { label: 'Dresses', singular: 'Dress', icon: '👗', x: 0.5, y: 0.42, scale: 0.48, z: 1 },
  outerwear: { label: 'Outerwear', singular: 'Jacket', icon: '🧥', x: 0.3, y: 0.3, scale: 0.48, z: 3 },
  shoes: { label: 'Shoes', singular: 'Shoes', icon: '👟', x: 0.5, y: 0.88, scale: 0.3, z: 4 },
  bags: { label: 'Bags', singular: 'Bag', icon: '👜', x: 0.82, y: 0.58, scale: 0.26, z: 5 },
  accessories: { label: 'Accessories', singular: 'Accessory', icon: '🕶️', x: 0.82, y: 0.15, scale: 0.22, z: 6 },
};

/** Words that identify each category, used for typed text ("denim jacket"). */
export const CATEGORY_KEYWORDS: [Category, string[]][] = [
  ['shoes', ['shoe', 'shoes', 'sneaker', 'sneakers', 'trainer', 'trainers', 'boot', 'boots', 'sandal', 'sandals', 'heel', 'heels', 'footwear', 'loafer', 'loafers', 'slipper', 'slippers', 'clog', 'clogs', 'flipflops', 'moccasin', 'pumps', 'mules', 'espadrilles', 'cleats']],
  ['bags', ['bag', 'bags', 'handbag', 'purse', 'backpack', 'tote', 'satchel', 'clutch', 'briefcase', 'wallet', 'duffel', 'crossbody']],
  ['dresses', ['dress', 'dresses', 'gown', 'sundress', 'jumpsuit', 'romper', 'playsuit', 'kimono', 'sari']],
  ['outerwear', ['coat', 'jacket', 'parka', 'blazer', 'raincoat', 'overcoat', 'trenchcoat', 'trench', 'windbreaker', 'gilet', 'vest', 'poncho', 'cape', 'outerwear', 'anorak', 'puffer', 'fleece', 'bomber']],
  ['bottoms', ['jeans', 'denim', 'pants', 'trousers', 'trouser', 'shorts', 'skirt', 'leggings', 'sweatpants', 'joggers', 'chinos', 'slacks', 'cargos']],
  ['tops', ['shirt', 'tshirt', 'tee', 'blouse', 'sweater', 'jumper', 'hoodie', 'sweatshirt', 'jersey', 'polo', 'cardigan', 'tank', 'turtleneck', 'pullover', 'top', 'camisole', 'tunic', 'crewneck']],
  ['accessories', ['hat', 'cap', 'beanie', 'scarf', 'glove', 'gloves', 'sunglasses', 'glasses', 'belt', 'tie', 'necktie', 'bowtie', 'watch', 'jewelry', 'jewellery', 'necklace', 'bracelet', 'earring', 'earrings', 'ring', 'headband', 'bandana', 'socks', 'umbrella']],
];

function tokens(text: string): Set<string> {
  const parts = text.toLowerCase().split(/[^a-z]+/).filter(Boolean);
  return new Set([...parts, parts.join('')]);
}

/** Category implied by free text such as "running shoes", or null. */
export function categoryFromText(text: string): Category | null {
  const words = tokens(text);
  let best: { category: Category; hits: number } | null = null;
  for (const [category, keywords] of CATEGORY_KEYWORDS) {
    const hits = keywords.filter((k) => words.has(k)).length;
    if (hits > (best?.hits ?? 0)) best = { category, hits };
  }
  return best?.category ?? null;
}
