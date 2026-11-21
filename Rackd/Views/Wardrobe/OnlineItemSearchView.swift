import SwiftUI

/// What the user picked from an online search.
struct OnlineSearchPick {
    let image: UIImage
    let brand: String
    let type: String
}

/// Type a brand and item type, search the web for product photos, pick one.
struct OnlineItemSearchView: View {
    let onPick: (OnlineSearchPick) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(ImageSearchSettings.providerKey) private var providerRaw = ImageSearchProviderKind.brave.rawValue
    @AppStorage("imageSearchPreferProductShots") private var preferProductShots = true

    @State private var brand = ""
    @State private var type = ""
    @State private var color = ""
    @State private var results: [ProductImageResult] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var errorMessage: String?
    @State private var downloadingID: UUID?
    @State private var showSettings = false
    @State private var hasAPIKey = false
    @FocusState private var focusedField: Field?

    private enum Field { case brand, type, color }

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    private var canSearch: Bool {
        !(brand + type).trimmingCharacters(in: .whitespaces).isEmpty && !isSearching
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    form

                    if !hasAPIKey {
                        setupPrompt
                    } else if isSearching {
                        ProgressView("Searching…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .padding(.top, 8)
                    } else if hasSearched && results.isEmpty {
                        ContentUnavailableView.search
                    } else if !results.isEmpty {
                        Text("Tap the photo that matches your item. Its background will be removed automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        resultsGrid
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Find Online")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Search settings")
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: refreshKeyState) {
                ImageSearchSettingsView()
            }
            .onAppear {
                refreshKeyState()
                focusedField = .brand
            }
            .onChange(of: providerRaw) { _, _ in refreshKeyState() }
            .disabled(downloadingID != nil)
        }
    }

    private var form: some View {
        VStack(spacing: 10) {
            TextField("Brand (e.g. Levi's)", text: $brand)
                .focused($focusedField, equals: .brand)
                .submitLabel(.next)
                .onSubmit { focusedField = .type }
            TextField("Type (e.g. 501 jeans)", text: $type)
                .focused($focusedField, equals: .type)
                .submitLabel(.next)
                .onSubmit { focusedField = .color }
            TextField("Colour (optional)", text: $color)
                .focused($focusedField, equals: .color)
                .submitLabel(.search)
                .onSubmit { Task { await search() } }

            Toggle("Prefer clean product shots", isOn: $preferProductShots)
                .font(.subheadline)

            Button {
                Task { await search() }
            } label: {
                Label("Search", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSearch || !hasAPIKey)
        }
        .textFieldStyle(.roundedBorder)
        .autocorrectionDisabled()
    }

    private var setupPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Connect an image search service", systemImage: "key")
                .font(.headline)
            Text("Rackd uses an image search API to find product photos. Add a free Brave Search API key (or a SerpApi key) to get started.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Open Settings") { showSettings = true }
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var resultsGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(results) { result in
                Button {
                    Task { await pick(result) }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                        AsyncImage(url: result.thumbnailURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFit()
                            case .failure:
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            default:
                                ProgressView()
                            }
                        }
                        .padding(6)
                        if downloadingID == result.id {
                            Color.black.opacity(0.35)
                            ProgressView().tint(.white)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(result.title.isEmpty ? "Search result" : result.title)
            }
        }
    }

    private func refreshKeyState() {
        hasAPIKey = ImageSearchSettings.currentProvider() != nil
    }

    private func search() async {
        guard canSearch, let provider = ImageSearchSettings.currentProvider() else { return }
        focusedField = nil
        isSearching = true
        errorMessage = nil
        defer {
            isSearching = false
            hasSearched = true
        }
        let query = ImageSearchSettings.query(
            brand: brand, type: type, color: color, preferProductShots: preferProductShots
        )
        do {
            results = try await provider.search(query: query)
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
    }

    private func pick(_ result: ProductImageResult) async {
        downloadingID = result.id
        defer { downloadingID = nil }
        do {
            let image = try await ImageSearchHTTP.downloadImage(for: result)
            onPick(OnlineSearchPick(
                image: image,
                brand: brand.trimmingCharacters(in: .whitespaces),
                type: [color, type]
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            ))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Choose the search provider and store its API key (in the Keychain).
struct ImageSearchSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(ImageSearchSettings.providerKey) private var providerRaw = ImageSearchProviderKind.brave.rawValue
    @State private var apiKey = ""

    private var provider: ImageSearchProviderKind {
        ImageSearchProviderKind(rawValue: providerRaw) ?? .brave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Service", selection: $providerRaw) {
                        ForEach(ImageSearchProviderKind.allCases) { kind in
                            Text(kind.displayName).tag(kind.rawValue)
                        }
                    }
                } footer: {
                    Text(provider.blurb)
                }

                Section("API Key") {
                    SecureField("Paste your API key", text: $apiKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Get a \(provider.displayName) key") {
                        openURL(provider.signupURL)
                    }
                }

                Section {
                    Text("Your searches (brand, type and colour) are sent to \(provider.displayName). The key is stored securely in your iPhone's Keychain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Online Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        ImageSearchSettings.setAPIKey(apiKey, for: provider)
                        dismiss()
                    }
                }
            }
            .onAppear { apiKey = ImageSearchSettings.apiKey(for: provider) ?? "" }
            .onChange(of: providerRaw) { _, _ in
                apiKey = ImageSearchSettings.apiKey(for: provider) ?? ""
            }
        }
    }
}
