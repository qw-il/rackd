import SwiftData
import SwiftUI

struct ItemDetailView: View {
    @Bindable var item: ClothingItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var isReprocessing = false
    @State private var reprocessFailed = false

    var body: some View {
        Form {
            Section {
                ZStack {
                    CheckerboardBackground(squareSize: 12)
                    ItemImageView(item: item)
                        .padding()
                    if isReprocessing {
                        ProgressView()
                            .controlSize(.large)
                    }
                }
                .frame(height: 320)
                .listRowInsets(EdgeInsets())
            }

            Section("Details") {
                TextField("Name", text: $item.name)

                Picker("Category", selection: $item.category) {
                    ForEach(ClothingCategory.allCases) { category in
                        Label(category.displayName, systemImage: category.symbolName).tag(category)
                    }
                }

                HStack {
                    Text("Colour")
                    Spacer()
                    if !item.colorHex.isEmpty {
                        ColorSwatch(hex: item.colorHex)
                    }
                    TextField("Colour", text: $item.colorName)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 140)
                }

                TextField("Brand", text: $item.brand)

                Toggle(isOn: $item.isFavorite) {
                    Label("Favourite", systemImage: "heart")
                }
            }

            Section("Notes") {
                TextField("Size, fit, care instructions…", text: $item.notes, axis: .vertical)
                    .lineLimit(2...6)
            }

            Section("Wear History") {
                let worn = item.wornDates
                LabeledContent("Times worn", value: "\(worn.count)")
                LabeledContent("Last worn", value: worn.last.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Never")
                LabeledContent("Added", value: item.createdAt.formatted(date: .abbreviated, time: .omitted))
            }

            if !item.outfits.isEmpty {
                Section("In \(item.outfits.count) Outfit\(item.outfits.count == 1 ? "" : "s")") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(item.outfits) { outfit in
                                VStack(spacing: 4) {
                                    OutfitPreview(outfit: outfit)
                                        .frame(width: 90)
                                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                                    Text(outfit.displayName)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .frame(width: 90)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                if item.originalImageData != nil {
                    Button {
                        Task { await redoBackgroundRemoval() }
                    } label: {
                        Label("Redo Background Removal", systemImage: "wand.and.stars")
                    }
                    .disabled(isReprocessing)

                    Button {
                        restoreOriginal()
                    } label: {
                        Label("Use Original Photo", systemImage: "photo")
                    }
                    .disabled(isReprocessing)
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Item", systemImage: "trash")
                }
            }
        }
        .navigationTitle(item.name.isEmpty ? item.category.singularName : item.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                // Pop first so this view doesn't re-render a deleted model.
                let context = modelContext
                let doomed = item
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    context.delete(doomed)
                }
            }
        } message: {
            Text("It will also be removed from any outfits.")
        }
        .alert("Couldn't find the item", isPresented: $reprocessFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try retaking the photo on a plain, contrasting background. Background removal needs a real device (not the Simulator).")
        }
    }

    private func redoBackgroundRemoval() async {
        guard let data = item.originalImageData, let original = UIImage(data: data) else { return }
        isReprocessing = true
        defer { isReprocessing = false }
        if let cutout = await ItemProcessor.removeBackground(original) {
            item.replaceImage(with: cutout.pngDataForStorage())
        } else {
            reprocessFailed = true
        }
    }

    private func restoreOriginal() {
        guard let data = item.originalImageData, let original = UIImage(data: data) else { return }
        item.replaceImage(with: original.pngDataForStorage())
    }
}
