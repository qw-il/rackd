import SwiftUI

/// Shows an item's cut-out image, decoded through the shared cache.
struct ItemImageView: View {
    let item: ClothingItem

    var body: some View {
        if let image = ImageCache.shared.image(for: item) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: item.category.symbolName)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A square tile with the item floating on a soft background.
struct ItemTile: View {
    let item: ClothingItem
    var showsName = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemBackground))
                ItemImageView(item: item)
                    .padding(10)
                if item.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.pink)
                        .padding(8)
                }
            }
            .aspectRatio(1, contentMode: .fit)

            if showsName {
                Text(item.name.isEmpty ? item.category.singularName : item.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
        }
    }
}

struct ColorSwatch: View {
    let hex: String
    var size: CGFloat = 14

    var body: some View {
        Circle()
            .fill(Color(hex: hex) ?? .gray)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.primary.opacity(0.15)))
    }
}

/// A pill-shaped filter chip.
struct Chip: View {
    let title: String
    var systemImage: String?
    var count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                if let count {
                    Text("\(count)")
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// Renders a saved outfit's layout at any size.
struct OutfitPreview: View {
    let outfit: Outfit

    var body: some View {
        OutfitCanvasRenderer(entries: outfit.resolvedPlacements)
    }
}

/// Non-interactive outfit renderer shared by previews and thumbnails.
struct OutfitCanvasRenderer: View {
    let entries: [CanvasEntry]

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                ForEach(entries) { entry in
                    ItemImageView(item: entry.item)
                        .frame(width: size.width * entry.placement.scale)
                        .position(x: size.width * entry.placement.x, y: size.height * entry.placement.y)
                        .zIndex(Double(entry.placement.zIndex))
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
    }
}

extension Color {
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
