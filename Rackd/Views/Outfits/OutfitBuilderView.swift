import SwiftData
import SwiftUI

/// Compose an outfit by tapping items from the tray, then drag to move and
/// pinch to resize them on the canvas.
struct OutfitBuilderView: View {
    /// The outfit being edited, or `nil` to create a new one.
    var outfit: Outfit?
    /// Called after the outfit is saved (e.g. to schedule it on the calendar).
    var onSave: ((Outfit) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ClothingItem.createdAt, order: .reverse) private var allItems: [ClothingItem]

    @State private var name = ""
    @State private var entries: [CanvasEntry] = []
    @State private var selectedID: UUID?
    @State private var trayCategory: ClothingCategory = .tops
    @State private var didLoad = false

    /// Categories where picking a new item swaps out the current one.
    private let singleSlotCategories: Set<ClothingCategory> = [.tops, .bottoms, .dresses, .outerwear, .shoes]

    private var availableCategories: [ClothingCategory] {
        ClothingCategory.allCases.filter { category in allItems.contains { $0.category == category } }
    }

    private var trayItems: [ClothingItem] {
        allItems.filter { $0.category == trayCategory }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Outfit name", text: $name)
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                canvas
                    .padding(.horizontal)

                canvasControls
                    .padding(.vertical, 8)

                Divider()

                tray
            }
            .navigationTitle(outfit == nil ? "New Outfit" : "Edit Outfit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(entries.isEmpty)
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.secondarySystemBackground))
                    .contentShape(Rectangle())
                    .onTapGesture { selectedID = nil }

                if entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "hand.tap")
                            .font(.largeTitle)
                        Text("Tap clothes below to add them.\nDrag to move, pinch to resize.")
                            .multilineTextAlignment(.center)
                            .font(.callout)
                    }
                    .foregroundStyle(.secondary)
                }

                ForEach($entries) { $entry in
                    EditableCanvasItem(
                        entry: $entry,
                        canvasSize: proxy.size,
                        isSelected: selectedID == entry.id,
                        onSelect: { select(entry.id) }
                    )
                    .zIndex(Double(entry.placement.zIndex))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
    }

    private var canvasControls: some View {
        HStack(spacing: 20) {
            Button {
                withAnimation(.spring) { shuffle() }
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
            .disabled(allItems.isEmpty)

            Spacer()

            if let selectedID {
                Button {
                    withAnimation { resetPlacement(selectedID) }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("Reset position")

                Button(role: .destructive) {
                    withAnimation { remove(selectedID) }
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Remove from outfit")
            } else if !entries.isEmpty {
                Button("Clear", role: .destructive) {
                    withAnimation { entries.removeAll() }
                }
            }
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 24)
    }

    // MARK: Tray

    private var tray: some View {
        VStack(alignment: .leading, spacing: 8) {
            if allItems.isEmpty {
                ContentUnavailableView(
                    "No clothes yet",
                    systemImage: "hanger",
                    description: Text("Add items in the Wardrobe tab first.")
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableCategories) { category in
                            Chip(
                                title: category.displayName,
                                systemImage: category.symbolName,
                                isSelected: trayCategory == category
                            ) {
                                trayCategory = category
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(trayItems) { item in
                            let isInOutfit = entries.contains { $0.item.id == item.id }
                            Button {
                                withAnimation(.spring(duration: 0.3)) { toggle(item) }
                            } label: {
                                ItemTile(item: item, showsName: false)
                                    .frame(width: 84)
                                    .overlay(alignment: .bottomTrailing) {
                                        if isInOutfit {
                                            Image(systemName: "checkmark.circle.fill")
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, Color.accentColor)
                                                .font(.title3)
                                                .padding(4)
                                        }
                                    }
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14)
                                            .strokeBorder(isInOutfit ? Color.accentColor : .clear, lineWidth: 2)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 96)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: 170)
    }

    // MARK: Actions

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        if let outfit {
            name = outfit.name
            entries = outfit.resolvedPlacements
        }
        if let first = availableCategories.first, !availableCategories.contains(trayCategory) {
            trayCategory = first
        }
    }

    private func select(_ id: UUID) {
        selectedID = id
        // Bring the selected item to the front.
        let top = (entries.map(\.placement.zIndex).max() ?? 0) + 1
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].placement.zIndex = top
        }
    }

    private func toggle(_ item: ClothingItem) {
        if let index = entries.firstIndex(where: { $0.item.id == item.id }) {
            if selectedID == item.id { selectedID = nil }
            entries.remove(at: index)
            return
        }

        var placement = OutfitPlacement.default(for: item)
        if singleSlotCategories.contains(item.category),
           let existing = entries.firstIndex(where: { $0.item.category == item.category }) {
            // Swap: keep the old item's position and size.
            let old = entries[existing].placement
            placement.x = old.x
            placement.y = old.y
            placement.scale = old.scale
            placement.zIndex = old.zIndex
            entries.remove(at: existing)
        }
        entries.append(CanvasEntry(placement: placement, item: item))
    }

    private func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        selectedID = nil
    }

    private func resetPlacement(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].placement = .default(for: entries[index].item)
    }

    private func shuffle() {
        func pick(_ category: ClothingCategory) -> ClothingItem? {
            allItems.filter { $0.category == category }.randomElement()
        }

        var picked: [ClothingItem] = []
        let hasSeparates = pick(.tops) != nil && pick(.bottoms) != nil
        if let dress = pick(.dresses), !hasSeparates || Bool.random() {
            picked.append(dress)
        } else {
            picked += [pick(.tops), pick(.bottoms)].compactMap { $0 }
        }
        if let shoes = pick(.shoes) { picked.append(shoes) }
        if Double.random(in: 0...1) < 0.4, let jacket = pick(.outerwear) { picked.append(jacket) }
        if Double.random(in: 0...1) < 0.35, let bag = pick(.bags) { picked.append(bag) }
        if Double.random(in: 0...1) < 0.35, let accessory = pick(.accessories) { picked.append(accessory) }

        if picked.isEmpty, let any = allItems.randomElement() { picked = [any] }

        selectedID = nil
        entries = picked.map { CanvasEntry(placement: .default(for: $0), item: $0) }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let items = entries.map(\.item)
        let placements = entries.map(\.placement)

        let saved: Outfit
        if let outfit {
            outfit.name = trimmedName
            outfit.items = items
            outfit.placements = placements
            saved = outfit
        } else {
            saved = Outfit(name: trimmedName, items: [], placements: placements)
            modelContext.insert(saved)
            saved.items = items
        }
        onSave?(saved)
        dismiss()
    }
}

/// A single draggable, pinchable item on the builder canvas.
private struct EditableCanvasItem: View {
    @Binding var entry: CanvasEntry
    let canvasSize: CGSize
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var pinchScale: CGFloat = 1
    @State private var isDragging = false

    var body: some View {
        ItemImageView(item: entry.item)
            .frame(width: canvasSize.width * entry.placement.scale * pinchScale)
            .padding(4)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
            }
            .shadow(color: .black.opacity(isDragging ? 0.25 : 0), radius: 8, y: 4)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .gesture(dragGesture.simultaneously(with: magnifyGesture))
            .position(
                x: canvasSize.width * entry.placement.x + dragOffset.width,
                y: canvasSize.height * entry.placement.y + dragOffset.height
            )
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    onSelect()
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                guard canvasSize.width > 0, canvasSize.height > 0 else { return }
                let newX = entry.placement.x + value.translation.width / canvasSize.width
                let newY = entry.placement.y + value.translation.height / canvasSize.height
                entry.placement.x = min(max(newX, 0.05), 0.95)
                entry.placement.y = min(max(newY, 0.05), 0.95)
                dragOffset = .zero
                isDragging = false
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                pinchScale = value.magnification
            }
            .onEnded { value in
                entry.placement.scale = min(max(entry.placement.scale * value.magnification, 0.08), 1.2)
                pinchScale = 1
            }
    }
}
