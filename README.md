# Rackd: personal wardrobe assistant (web app)

A mobile-first web app for cataloguing your clothes, building outfits and planning what to wear. It works in any modern browser, and on iPhone you can use **Share → Add to Home Screen** to get a full-screen app with the Rackd icon.

All your data stays in your browser's local storage (IndexedDB). Nothing is uploaded except optional brand searches, described below.

## Features

### Digital wardrobe
- **Add clothes** by taking a photo (opens the phone camera) or uploading up to 20 photos at once.
- **Automatic background removal** runs entirely in the browser using an AI segmentation model (`@imgly/background-removal`, the model files are served by this app). If that fails, a backup method removes plain backgrounds such as a wall, floor, bedsheet or a product shot's white backdrop. Stray specks are cleaned up and the image is cropped to the item.
- **Automatic categorisation** uses CLIP zero-shot image classification (`@huggingface/transformers`, runs in the browser) to sort items into Tops, Bottoms, Dresses, Outerwear, Shoes, Bags or Accessories. If the model can't load, the app guesses from the item's shape.
- **Colour detection** finds the dominant colour and names it (e.g. "Navy", "Olive").
- **Find online by brand** (optional): type a brand, type and colour (e.g. "Levi's", "501 jeans", "black") and pick a product photo from web results. The brand, name and category are filled in from what you typed.
- A review screen lets you correct everything before saving. The wardrobe is grouped by category, with filter chips, search and favourites.
- The item page lets you edit details, see wear count and last worn date, see which outfits use the item, redo background removal or use the original photo.

### Outfit builder
- Tap clothes in the tray to add them to a canvas. Picking another top, bottom, dress, outerwear piece or pair of shoes swaps it in.
- Drag to move items. Resize with a pinch, the mouse wheel or the size slider. Tapping an item brings it to the front.
- **Shuffle** generates a random outfit from what you own.

### Outfit calendar
- A month grid shows a thumbnail of each day's outfit. Swipe or use the arrows to change month.
- Plan any saved outfit for a day, or build a new one straight from the calendar.
- Past days count as "worn" and feed the wear statistics.

## Running it

Requires Node.js 20.12 or later.

```bash
npm install
npm run dev        # development server at http://localhost:5173
```

Production:

```bash
npm run build
npm start          # serves dist/ and the API at http://localhost:8787 (PORT to change)
```

`npm run build` copies the background-removal model (~85 MB) from `node_modules` into `public/imgly/`, so the app doesn't depend on a third-party CDN for it. The clothing recogniser (~90 MB) downloads from Hugging Face the first time it's used, then the browser caches it.

> The camera button uses the phone's camera when the site is opened over **HTTPS** (or `localhost`). To try it on your phone during development, use an HTTPS tunnel or deploy it.

### Optional: online search by brand
Copy `.env.example` to `.env` and set **one** key:

- `BRAVE_API_KEY`: Brave Search API, which has a free plan (https://brave.com/search/api/)
- `SERPAPI_KEY`: SerpApi with Google Images results (https://serpapi.com/)

The key stays on the server and is never sent to the browser. The server also downloads the chosen image for the browser (some shops block direct use), and blocks requests to private or local network addresses. Without a key, or on static hosting, the "Find Online" option is simply hidden.

### Deploying
- **With search:** run `npm run build && npm start` on any Node host (Render, Railway, Fly.io, a VPS…) behind HTTPS.
- **Without search:** `dist/` is a static site and can be hosted anywhere (Netlify, Vercel, GitHub Pages, S3…). Configure a single-page-app fallback to `index.html`.

## Licensing note
`@imgly/background-removal` is licensed under the **AGPL-3.0**. If you deploy Rackd publicly, the AGPL requires you to make this app's source code available to its users (keeping this repository public satisfies that), or to buy a commercial licence from IMG.LY. Check the licence terms before choosing a licence for this project.

## Project layout
```
index.html, public/            App shell, icons, web app manifest
src/
  main.tsx                     Routes and tab bar
  db.ts                        IndexedDB (Dexie): items, outfits, plans
  lib/
    processItem.ts             Photo → background removed → category → colour
    backgroundRemoval.ts       AI segmentation + fallback
    plainBackground.ts         Plain-background flood-fill remover
    classifier.ts              CLIP zero-shot clothing categories
    categories.ts              Categories, canvas defaults, text → category
    color.ts, imageUtils.ts    Colour naming, canvas helpers, mask clean-up
    onlineSearch.ts            Client for the search API
  pages/                       Wardrobe, AddItems, OnlineSearch, ItemDetail,
                               Outfits (+ detail), OutfitBuilder, Calendar
server/
  api.mjs                      /api/config, /api/search, /api/image (shared by dev + prod)
  server.mjs                   Production static server + API
scripts/copy-imgly-assets.mjs  Copies the model files into public/imgly
```
