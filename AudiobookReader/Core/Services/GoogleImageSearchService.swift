import Foundation
import UIKit

class GoogleImageSearchService {
    static let shared = GoogleImageSearchService()
    
    // Google Custom Search API configuration
    // Note: You'll need to set up a Google Custom Search Engine and get these keys
    // For development, we'll provide fallback mock data if API keys aren't configured
    private let apiKey = "" // Add your Google API key here
    private let searchEngineId = "" // Add your Custom Search Engine ID here
    
    private init() {}
    
    func searchImages(query: String) async -> Result<[ImageSearchResult], GoogleImageSearchError> {
        // Check if API keys are configured
        guard !apiKey.isEmpty && !searchEngineId.isEmpty else {
            // Return mock data with realistic book cover placeholders for development
            return await createMockSearchResults(for: query)
        }
        
        // Perform real Google Custom Search API call
        return await performRealSearch(query: query)
    }
    
    private func performRealSearch(query: String) async -> Result<[ImageSearchResult], GoogleImageSearchError> {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return .failure(.invalidQuery)
        }
        
        let urlString = "https://www.googleapis.com/customsearch/v1" +
                       "?key=\(apiKey)" +
                       "&cx=\(searchEngineId)" +
                       "&q=\(encodedQuery)" +
                       "&searchType=image" +
                       "&num=10" +
                       "&safe=active" +
                       "&imgSize=medium" +
                       "&imgType=photo"
        
        guard let url = URL(string: urlString) else {
            return .failure(.invalidURL)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return .failure(.networkError("HTTP Error: \((response as? HTTPURLResponse)?.statusCode ?? 0)"))
            }
            
            let searchResponse = try JSONDecoder().decode(GoogleCustomSearchResponse.self, from: data)
            
            let results = searchResponse.items?.compactMap { item -> ImageSearchResult? in
                guard let link = item.link,
                      let thumbnail = item.image?.thumbnailLink else {
                    return nil
                }
                
                return ImageSearchResult(
                    id: item.cacheId ?? UUID().uuidString,
                    thumbnailUrl: thumbnail,
                    fullUrl: link,
                    title: item.title
                )
            } ?? []
            
            return .success(results)
            
        } catch {
            return .failure(.decodingError(error))
        }
    }
    
    private func createMockSearchResults(for query: String) async -> Result<[ImageSearchResult], GoogleImageSearchError> {
        // Simulate network delay
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Create realistic mock results with book cover style images
        let mockResults = [
            ImageSearchResult(
                id: "mock_1",
                thumbnailUrl: "https://picsum.photos/200/300?random=1",
                fullUrl: "https://picsum.photos/400/600?random=1",
                title: "Book Cover 1"
            ),
            ImageSearchResult(
                id: "mock_2",
                thumbnailUrl: "https://picsum.photos/200/300?random=2",
                fullUrl: "https://picsum.photos/400/600?random=2",
                title: "Book Cover 2"
            ),
            ImageSearchResult(
                id: "mock_3",
                thumbnailUrl: "https://picsum.photos/200/300?random=3",
                fullUrl: "https://picsum.photos/400/600?random=3",
                title: "Book Cover 3"
            ),
            ImageSearchResult(
                id: "mock_4",
                thumbnailUrl: "https://picsum.photos/200/300?random=4",
                fullUrl: "https://picsum.photos/400/600?random=4",
                title: "Book Cover 4"
            ),
            ImageSearchResult(
                id: "mock_5",
                thumbnailUrl: "https://picsum.photos/200/300?random=5",
                fullUrl: "https://picsum.photos/400/600?random=5",
                title: "Book Cover 5"
            ),
            ImageSearchResult(
                id: "mock_6",
                thumbnailUrl: "https://picsum.photos/200/300?random=6",
                fullUrl: "https://picsum.photos/400/600?random=6",
                title: "Book Cover 6"
            )
        ]
        
        return .success(mockResults)
    }
}

// MARK: - Data Models

struct ImageSearchResult {
    let id: String
    let thumbnailUrl: String
    let fullUrl: String
    let title: String?
    
    init(id: String, thumbnailUrl: String, fullUrl: String, title: String? = nil) {
        self.id = id
        self.thumbnailUrl = thumbnailUrl
        self.fullUrl = fullUrl
        self.title = title
    }
}

enum GoogleImageSearchError: Error, LocalizedError {
    case invalidQuery
    case invalidURL
    case networkError(String)
    case decodingError(Error)
    case apiKeyNotConfigured
    
    var errorDescription: String? {
        switch self {
        case .invalidQuery:
            return "Invalid search query"
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .apiKeyNotConfigured:
            return "Google API key not configured"
        }
    }
}

// MARK: - Google Custom Search API Response Models

private struct GoogleCustomSearchResponse: Codable {
    let items: [GoogleCustomSearchItem]?
}

private struct GoogleCustomSearchItem: Codable {
    let title: String?
    let link: String?
    let cacheId: String?
    let image: GoogleCustomSearchImage?
}

private struct GoogleCustomSearchImage: Codable {
    let thumbnailLink: String?
    let thumbnailHeight: Int?
    let thumbnailWidth: Int?
}