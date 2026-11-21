import SwiftData
import SwiftUI

/// An item being reviewed before it's saved to the wardrobe.
struct ItemDraft: Identifiable {
    let id = UUID()
    var processed: ProcessedItem
    var name: String
    var category: ClothingCategory
    var useCutout: Bool

    init(_ processed: ProcessedItem) {
        self.processed = processed
        self.name = processed.suggestedName
        self.category = processed.category
        self.useCutout = processed.backgroundRemoved
    }

    var displayImage: UIImage {
        useCutout ? processed.cutout : processed.original
    }
}

/// Runs each photo through background removal + categorization, then lets the
/// user confirm or tweak the results before saving.
struct AddItemsView: View {
    let images: [UIImage]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [ItemDraft] = []
    @State private var isProcessing = true

    var body: some View {
        NavigationStack {
            List {
                if isProcessing {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            VStack(alignment: .leading) {
                                Text("Processing \(min(drafts.count + 1, images.count)) of \(images.count)…")
                                Text("Removing backgrounds and sorting into categories")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    ForEach($drafts) { $draft in
                        DraftRow(draft: $draft)
                    }
                    .onDelete { drafts.remove(atOffsets: $0) }
                } footer: {
                    if !drafts.isEmpty {
                        Text("Categories were detected automatically. Tap one to change it.")
                    }
                }
            }
            .navigationTitle(images.count == 1 ? "New Item" : "New Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(drafts.count > 1 ? "Save All" : "Save") { save() }
                        .disabled(isProcessing || drafts.isEmpty)
                }
            }
            .interactiveDismissDisabled(isProcessing)
            .task { await processAll() }
        }
    }

    private func processAll() async {
        guard drafts.isEmpty else { return }
        for image in images {
            let processed = await ItemProcessor.process(image)
            withAnimation { drafts.append(ItemDraft(processed)) }
        }
        isProcessing = false
    }

    private func save() {
        for draft in drafts {
            let item = ClothingItem(
                name: draft.name.trimmingCharacters(in: .whitespaces),
                category: draft.category,
                imageData: draft.displayImage.pngDataForStorage(),
                originalImageData: draft.processed.original.jpegData(compressionQuality: 0.8),
                colorName: draft.processed.colorName,
                colorHex: draft.processed.colorHex
            )
            modelContext.insert(item)
        }
        dismiss()
    }
}

private struct DraftRow: View {
    @Binding var draft: ItemDraft

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(uiImage: draft.displayImage)
                .resizable()
                .scaledToFit()
                .padding(6)
                .frame(width: 88, height: 88)
                .background(CheckerboardBackground().clipShape(RoundedRectangle(cornerRadius: 10)))

            VStack(alignment: .leading, spacing: 6) {
                TextField("Name", text: $draft.name)
                    .font(.headline)

                Picker("Category", selection: $draft.category) {
                    ForEach(ClothingCategory.allCases) { category in
                        Label(category.displayName, systemImage: category.symbolName).tag(category)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()

                HStack(spacing: 6) {
                    if !draft.processed.colorHex.isEmpty {
                        ColorSwatch(hex: draft.processed.colorHex, size: 12)
                        Text(draft.processed.colorName)
                    }
                    if draft.category == draft.processed.category {
                        Text(confidenceText)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if draft.processed.backgroundRemoved {
                    Toggle("Remove background", isOn: $draft.useCutout)
                        .font(.caption)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                } else {
                    Label("Couldn't find the item's edges – keeping the full photo.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var confidenceText: String {
        switch draft.processed.categoryConfidence {
        case 0.6...: "· Auto-sorted"
        case 0.3..<0.6: "· Best guess"
        default: "· Please check category"
        }
    }
}

/// Grey/white checks so transparent cut-outs read clearly.
struct CheckerboardBackground: View {
    var squareSize: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(.systemBackground)))
            let columns = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(x: CGFloat(column) * squareSize, y: CGFloat(row) * squareSize,
                                      width: squareSize, height: squareSize)
                    context.fill(Path(rect), with: .color(Color(.tertiarySystemFill)))
                }
            }
        }
    }
}
