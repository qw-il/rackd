import Foundation
import Security
import UIKit

/// One image found online.
struct ProductImageResult: Identifiable, Hashable {
    let id = UUID()
    /// Small, fast-loading preview (always HTTPS from the search provider's CDN).
    let thumbnailURL: URL
    /// Full-size image on the original site, if known.
    let imageURL: URL?
    let title: String
    let source: String
}

enum ProductImageSearchError: LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case rateLimited
    case badResponse(Int)
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add a search API key in Settings to search online."
        case .invalidAPIKey: "The search API key was rejected. Check it in Settings."
        case .rateLimited: "Too many searches – the provider's rate limit was hit. Try again shortly."
        case .badResponse(let code): "The search service returned an error (\(code))."
        case .downloadFailed: "Couldn't download that image. Try another one."
        }
    }
}

protocol ProductImageSearchProvider {
    func search(query: String) async throws -> [ProductImageResult]
}

// MARK: - Providers

enum ImageSearchProviderKind: String, CaseIterable, Identifiable {
    case brave
    case serpapi

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .brave: "Brave Search"
        case .serpapi: "SerpApi (Google Images)"
        }
    }

    var signupURL: URL {
        switch self {
        case .brave: URL(string: "https://brave.com/search/api/")!
        case .serpapi: URL(string: "https://serpapi.com/")!
        }
    }

    var blurb: String {
        switch self {
        case .brave: "Has a free plan. Create an API key for the Search API and paste it below."
        case .serpapi: "Google Images results. Has a free monthly allowance; paste your API key below."
        }
    }

    func makeProvider(apiKey: String) -> ProductImageSearchProvider {
        switch self {
        case .brave: BraveImageSearch(apiKey: apiKey)
        case .serpapi: SerpAPIImageSearch(apiKey: apiKey)
        }
    }
}

struct BraveImageSearch: ProductImageSearchProvider {
    let apiKey: String

    private struct Response: Decodable {
        struct Result: Decodable {
            struct Thumbnail: Decodable { let src: String? }
            struct Properties: Decodable { let url: String? }
            let title: String?
            let source: String?
            let thumbnail: Thumbnail?
            let properties: Properties?
        }
        let results: [Result]?
    }

    func search(query: String) async throws -> [ProductImageResult] {
        var components = URLComponents(string: "https://api.search.brave.com/res/v1/images/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "40"),
            URLQueryItem(name: "safesearch", value: "strict"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")

        let data = try await ImageSearchHTTP.fetch(request)
        let response = try JSONDecoder().decode(Response.self, from: data)
        return (response.results ?? []).compactMap { result in
            guard let thumb = result.thumbnail?.src.flatMap(URL.init(string:)) else { return nil }
            return ProductImageResult(
                thumbnailURL: thumb,
                imageURL: result.properties?.url.flatMap(URL.init(string:)),
                title: result.title ?? "",
                source: result.source ?? ""
            )
        }
    }
}

struct SerpAPIImageSearch: ProductImageSearchProvider {
    let apiKey: String

    private struct Response: Decodable {
        struct Result: Decodable {
            let thumbnail: String?
            let original: String?
            let title: String?
            let source: String?
        }
        let images_results: [Result]?
        let error: String?
    }

    func search(query: String) async throws -> [ProductImageResult] {
        var components = URLComponents(string: "https://serpapi.com/search.json")!
        components.queryItems = [
            URLQueryItem(name: "engine", value: "google_images"),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "safe", value: "active"),
            URLQueryItem(name: "api_key", value: apiKey),
        ]
        let data = try await ImageSearchHTTP.fetch(URLRequest(url: components.url!))
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let error = response.error, error.localizedCaseInsensitiveContains("api key") {
            throw ProductImageSearchError.invalidAPIKey
        }
        return (response.images_results ?? []).prefix(40).compactMap { result in
            guard let thumb = result.thumbnail.flatMap(URL.init(string:)) else { return nil }
            return ProductImageResult(
                thumbnailURL: thumb,
                imageURL: result.original.flatMap(URL.init(string:)),
                title: result.title ?? "",
                source: result.source ?? ""
            )
        }
    }
}

enum ImageSearchHTTP {
    static func fetch(_ request: URLRequest) async throws -> Data {
        var request = request
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProductImageSearchError.badResponse(0) }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw ProductImageSearchError.invalidAPIKey
        case 429: throw ProductImageSearchError.rateLimited
        default: throw ProductImageSearchError.badResponse(http.statusCode)
        }
    }

    /// Downloads the full-size image, falling back to the thumbnail if the
    /// original site blocks the request or serves something that isn't an image.
    static func downloadImage(for result: ProductImageResult) async throws -> UIImage {
        for url in [result.imageURL, result.thumbnailURL].compactMap({ $0 }) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            // Some shops refuse requests without a browser-like Accept header.
            request.setValue("image/avif,image/webp,image/png,image/jpeg,image/*;q=0.8", forHTTPHeaderField: "Accept")
            guard let download = try? await URLSession.shared.data(for: request) else { continue }
            let status = (download.1 as? HTTPURLResponse)?.statusCode ?? 200
            if status < 300, let image = UIImage(data: download.0) {
                return image
            }
        }
        throw ProductImageSearchError.downloadFailed
    }
}

// MARK: - Settings

enum ImageSearchSettings {
    static let providerKey = "imageSearchProvider"

    static var provider: ImageSearchProviderKind {
        UserDefaults.standard.string(forKey: providerKey).flatMap { ImageSearchProviderKind(rawValue: $0) } ?? .brave
    }

    static func apiKey(for provider: ImageSearchProviderKind) -> String? {
        KeychainStore.string(for: "apiKey.\(provider.rawValue)")
    }

    static func setAPIKey(_ key: String?, for provider: ImageSearchProviderKind) {
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainStore.set(trimmed?.isEmpty == false ? trimmed : nil, for: "apiKey.\(provider.rawValue)")
    }

    /// The configured provider, or `nil` if no API key has been entered.
    static func currentProvider() -> ProductImageSearchProvider? {
        let kind = provider
        guard let key = apiKey(for: kind), !key.isEmpty else { return nil }
        return kind.makeProvider(apiKey: key)
    }

    /// Builds the search query from what the user typed.
    static func query(brand: String, type: String, color: String, preferProductShots: Bool) -> String {
        var parts = [brand, color, type]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if preferProductShots { parts.append("product photo white background") }
        return parts.joined(separator: " ")
    }
}

/// Minimal Keychain wrapper so API keys aren't stored in plain UserDefaults.
enum KeychainStore {
    private static let service = "app.rackd.apikeys"

    static func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
