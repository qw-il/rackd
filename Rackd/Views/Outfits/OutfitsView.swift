import SwiftData
import SwiftUI

struct OutfitsView: View {
    @Query(sort: \Outfit.createdAt, order: .reverse) private var outfits: [Outfit]
    @Query private var items: [ClothingItem]
    @State private var showBuilder = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            Group {
                if outfits.isEmpty {
                    ContentUnavailableView {
                        Label("No outfits yet", systemImage: "square.stack.3d.up")
                    } description: {
                        Text(items.isEmpty
                             ? "Add some clothes to your wardrobe, then mix and match them here."
                             : "Mix and match your clothes into outfits.")
                    } actions: {
                        if !items.isEmpty {
                            Button("Build an Outfit") { showBuilder = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(outfits) { outfit in
                                NavigationLink(value: outfit) {
                                    OutfitCard(outfit: outfit)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Outfits")
            .navigationDestination(for: Outfit.self) { outfit in
                OutfitDetailView(outfit: outfit)
            }
            .navigationDestination(for: ClothingItem.self) { item in
                ItemDetailView(item: item)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showBuilder = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(items.isEmpty)
                    .accessibilityLabel("New outfit")
                }
            }
            .sheet(isPresented: $showBuilder) {
                OutfitBuilderView()
            }
        }
    }
}

struct OutfitCard: View {
    let outfit: Outfit

    private var nextPlan: Date? {
        let today = Calendar.current.startOfDay(for: Date())
        return outfit.plans.map(\.date).filter { $0 >= today }.min()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            OutfitPreview(outfit: outfit)
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

            Text(outfit.displayName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 4) {
                Text("\(outfit.items.count) item\(outfit.items.count == 1 ? "" : "s")")
                if let nextPlan {
                    Text("·")
                    Image(systemName: "calendar")
                    Text(nextPlan.formatted(.dateTime.month(.abbreviated).day()))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
