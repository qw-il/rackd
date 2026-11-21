import PhotosUI
import SwiftData
import SwiftUI

/// A batch of photos waiting to be processed and reviewed.
struct PendingImages: Identifiable {
    let id = UUID()
    let images: [UIImage]
    /// Pre-filled from an online search.
    var brand = ""
    var typeHint = ""
}

struct WardrobeView: View {
    @Query(sort: \ClothingItem.createdAt, order: .reverse) private var items: [ClothingItem]

    @State private var selectedCategory: ClothingCategory?
    @State private var searchText = ""
    @State private var favoritesOnly = false

    @State private var showCamera = false
    @State private var capturedImage: UIImage?
    @State private var showPhotoPicker = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false
    @State private var pending: PendingImages?
    @State private var showOnlineSearch = false
    @State private var onlinePick: OnlineSearchPick?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 12)]

    private var filteredItems: [ClothingItem] {
        items.filter { item in
            if let selectedCategory, item.category != selectedCategory { return false }
            if favoritesOnly && !item.isFavorite { return false }
            if !searchText.isEmpty {
                let haystack = [item.name, item.colorName, item.brand, item.category.displayName, item.notes]
                    .joined(separator: " ")
                return haystack.localizedCaseInsensitiveContains(searchText)
            }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            categoryChips
                            if filteredItems.isEmpty {
                                ContentUnavailableView.search(text: searchText)
                                    .padding(.top, 40)
                            } else if selectedCategory == nil {
                                groupedGrid
                            } else {
                                grid(filteredItems)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Wardrobe")
            .searchable(text: $searchText, prompt: "Search name, colour, brand")
            .navigationDestination(for: ClothingItem.self) { item in
                ItemDetailView(item: item)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        favoritesOnly.toggle()
                    } label: {
                        Image(systemName: favoritesOnly ? "heart.fill" : "heart")
                    }
                    .accessibilityLabel("Show favourites only")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    addMenu
                }
            }
            .overlay {
                if isLoadingPhotos {
                    ProgressView("Loading photos…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $photoSelection,
                maxSelectionCount: 20,
                matching: .images
            )
            .onChange(of: photoSelection) { _, newValue in
                guard !newValue.isEmpty else { return }
                Task { await loadPhotos(newValue) }
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                if let capturedImage {
                    pending = PendingImages(images: [capturedImage])
                    self.capturedImage = nil
                }
            }) {
                CameraPicker { capturedImage = $0 }
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showOnlineSearch, onDismiss: {
                if let onlinePick {
                    pending = PendingImages(images: [onlinePick.image], brand: onlinePick.brand, typeHint: onlinePick.type)
                    self.onlinePick = nil
                }
            }) {
                OnlineItemSearchView { onlinePick = $0 }
            }
            .sheet(item: $pending) { batch in
                AddItemsView(images: batch.images, brand: batch.brand, typeHint: batch.typeHint)
            }
        }
    }

    private var addMenu: some View {
        Menu {
            if CameraPicker.isAvailable {
                Button {
                    showCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }
            Button {
                showPhotoPicker = true
            } label: {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
            }
            Button {
                showOnlineSearch = true
            } label: {
                Label("Find Online by Brand", systemImage: "magnifyingglass")
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add clothes")
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Your wardrobe is empty", systemImage: "hanger")
        } description: {
            Text("Photograph your clothes, or find them online by brand. Rackd removes the background and sorts each item into a category for you.")
        } actions: {
            if CameraPicker.isAvailable {
                Button("Take Photo") { showCamera = true }
                    .buttonStyle(.borderedProminent)
            }
            Button("Choose from Library") { showPhotoPicker = true }
                .buttonStyle(.bordered)
            Button("Find Online by Brand") { showOnlineSearch = true }
                .buttonStyle(.bordered)
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(title: "All", count: items.count, isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(ClothingCategory.allCases) { category in
                    let count = items.filter { $0.category == category }.count
                    if count > 0 {
                        Chip(
                            title: category.displayName,
                            systemImage: category.symbolName,
                            count: count,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = selectedCategory == category ? nil : category
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var groupedGrid: some View {
        let groups = Dictionary(grouping: filteredItems, by: \.category)
        return VStack(alignment: .leading, spacing: 20) {
            ForEach(ClothingCategory.allCases) { category in
                if let categoryItems = groups[category], !categoryItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            selectedCategory = category
                        } label: {
                            HStack {
                                Label(category.displayName, systemImage: category.symbolName)
                                    .font(.headline)
                                Text("\(categoryItems.count)")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        grid(categoryItems)
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func grid(_ items: [ClothingItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    ItemTile(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadPhotos(_ selection: [PhotosPickerItem]) async {
        isLoadingPhotos = true
        var images: [UIImage] = []
        for pickerItem in selection {
            if let data = try? await pickerItem.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        isLoadingPhotos = false
        photoSelection = []
        if !images.isEmpty {
            pending = PendingImages(images: images)
        }
    }
}
