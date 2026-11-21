# Rackd: personal wardrobe assistant (iOS)

A SwiftUI + SwiftData iPhone app for cataloguing your clothes, building outfits and planning what to wear.

## Features

### Digital wardrobe
- **Photograph clothes** with the camera, or import up to 20 at once from your photo library.
- **Find it online by brand.** Type a brand and item type (e.g. "Levi's" + "501 jeans", plus an optional colour) and pick a clean product photo from web image results. The photo goes through the same background removal, and the brand, name and category are filled in from what you typed.
- **Automatic background removal.** Vision's on-device subject lifting (`VNGenerateForegroundInstanceMaskRequest`, the same tech as "Lift Subject" in Photos) cuts each item out onto a transparent background.
- **Automatic categorisation.** Vision's built-in image classifier (`VNClassifyImageRequest`) sorts each item into Tops, Bottoms, Dresses, Outerwear, Shoes, Bags or Accessories. If it finds no clothing labels, the app guesses from the item's shape.
- **Colour detection.** The app finds the item's dominant colour (ignoring the removed background) and names it, e.g. "Navy" or "Olive".
- A review screen shows each detected category, colour and suggested name (e.g. "Denim Jeans") so you can correct them before saving.
- The wardrobe is grouped by category, with filter chips, search (name/colour/brand/notes) and favourites.
- The item detail screen lets you edit fields, see wear count and last worn date, see which outfits use the item, redo background removal or revert to the original photo.

### Outfit builder
- Tap items in the category tray to add them to a canvas. Picking a second top, bottom, dress, outerwear piece or pair of shoes swaps it in.
- **Drag** to move items, **pinch** to resize. Tapping an item brings it to the front.
- **Shuffle** generates a random outfit (top + bottom, or a dress, plus shoes, and sometimes outerwear, a bag or accessories).
- Saved outfits keep their exact layout.

### Outfit calendar
- A month grid shows a thumbnail of each day's outfit. Swipe or use the arrows to change month.
- Plan an outfit for any day, either from your saved outfits or by building a new one on the spot.
- Past entries count as "worn" and feed the wear statistics on each item and outfit.

## Requirements
- Xcode 16 or later
- iOS 17.0 or later, iPhone

## Running it
1. Open `Rackd.xcodeproj` in Xcode.
2. Select the **Rackd** target → *Signing & Capabilities* → choose your Team. You may also need to change the bundle identifier (`com.example.rackd`) to something unique.
3. Run on an iPhone.

> **Use a real device.** Vision's background removal needs the Neural Engine and doesn't run in the iOS Simulator. In the Simulator, items are saved with their full photo, and the review screen tells you background removal failed. Everything else works in the Simulator, and the camera option only appears on devices that have a camera.

### Setting up online search
Online search needs an image search API key, which you enter in the app (Wardrobe → + → Find Online by Brand → ⚙︎). The key is stored in the iOS Keychain.
- **Brave Search API** (default): has a free plan. Get a key at https://brave.com/search/api/
- **SerpApi** (Google Images results): has a free monthly allowance. Get a key at https://serpapi.com/

Only the brand, type and colour you type are sent to the search service.

## Project layout
```
Rackd/
  RackdApp.swift              App entry, SwiftData container, tab bar
  Models/                     ClothingItem, Outfit (+ canvas layout), OutfitPlan, ClothingCategory
  Services/
    BackgroundRemover.swift   Vision subject lifting
    ClothingClassifier.swift  Vision classification → ClothingCategory
    ColorAnalyzer.swift       Dominant colour + name
    ItemProcessor.swift       Full photo → item pipeline (runs off the main thread)
    ImageCache.swift          Decoded-image cache
    ProductImageSearch.swift  Online product-photo search (Brave / SerpApi), Keychain key storage
  Views/
    Wardrobe/                 Grid, add/review flow, online search, item detail
    Outfits/                  Outfit list, builder canvas, outfit detail
    Calendar/                 Month grid, day detail, outfit picker
    Shared/                   Tiles, chips, camera picker, outfit renderer
```

All data stays on the device in SwiftData. Images use external storage so the database stays small.
