import Foundation

struct CatalogPage {
    let videos: [VideoItem]
    let categories: [VideoCategory]
    let page: Int
    let pageCount: Int?
    let total: Int?
    let hasMore: Bool
}

struct DoubanRecommendationPage: Sendable {
    let items: [DoubanRecommendation]
    let total: Int
    let start: Int
}

actor UZAPI {
    static let shared = UZAPI()
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 45
        configuration.requestCachePolicy = .reloadRevalidatingCacheData
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (AppleTV; U; CPU OS 18_2 like Mac OS X) AppleWebKit/605.1.15 uzVideo/1.6.67",
            "Accept": "application/json,text/plain,*/*"
        ]
        session = URLSession(configuration: configuration)
    }

    func sources(shareCode: String) async throws -> [VideoSource] {
        let code = shareCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { throw UZError.server("请输入视频源分享码") }
        var components = URLComponents(string: "https://api.616222.xyz/codeeeecodeeee/")!
        components.queryItems = [
            URLQueryItem(name: "type", value: "vod"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "version", value: "1667")
        ]
        guard let url = components.url else { throw UZError.invalidURL }
        let data = try await request(url)
        do {
            let result = try JSONDecoder().decode([VideoSource].self, from: data)
            guard !result.isEmpty else { throw UZError.server("分享码中没有视频源") }
            return result
        } catch let error as UZError {
            throw error
        } catch {
            throw UZError.server("分享码数据格式不正确：\(error.localizedDescription)")
        }
    }

    func subscription(shareCode: String) async throws -> Data {
        let code = shareCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { throw UZError.server("请输入订阅分享码") }
        var components = URLComponents(string: "https://api.616222.xyz/codeeeecodeeee/")!
        components.queryItems = [
            URLQueryItem(name: "type", value: "sub"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "version", value: "1667")
        ]
        guard let url = components.url else { throw UZError.invalidURL }
        return try await request(url)
    }

    func catalog(source: VideoSource, categoryID: Int? = nil, keyword: String? = nil, page: Int = 1) async throws -> CatalogPage {
        guard var components = URLComponents(string: source.api) else { throw UZError.invalidURL }
        var items = components.queryItems ?? []
        items.removeAll { ["ac", "pg", "wd", "t"].contains($0.name) }
        items.append(URLQueryItem(name: "ac", value: "detail"))
        items.append(URLQueryItem(name: "pg", value: String(max(1, page))))
        if let categoryID { items.append(URLQueryItem(name: "t", value: String(categoryID))) }
        if let keyword, !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            items.append(URLQueryItem(name: "wd", value: keyword.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        components.queryItems = items
        guard let url = components.url else { throw UZError.invalidURL }
        let data = try await request(url)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["list"] as? [[String: Any]] else {
            throw UZError.invalidResponse
        }
        var classes = (root["class"] as? [[String: Any]] ?? []).compactMap(VideoCategory.init)
        // Most MacCMS servers omit `class` from ac=detail and only return it for ac=list.
        // Keyword searches only need matching videos. Fetching categories here
        // doubled the number of requests when recommendation search fan-outs to
        // every source, and the result was discarded by that screen anyway.
        if page == 1 && keyword == nil && classes.isEmpty { classes = try await categories(source: source) }
        let currentPage = Self.int(root["page"]) ?? page
        let pageCount = Self.int(root["pagecount"])
        let total = Self.int(root["total"])
        let limit = Self.int(root["limit"])
        let hasMore: Bool
        if let pageCount {
            hasMore = currentPage < pageCount
        } else if let total, let limit, limit > 0 {
            hasMore = currentPage * limit < total
        } else {
            hasMore = !list.isEmpty
        }
        return CatalogPage(videos: list.map(VideoItem.init), categories: classes, page: currentPage, pageCount: pageCount, total: total, hasMore: hasMore)
    }

    func categories(source: VideoSource) async throws -> [VideoCategory] {
        guard var components = URLComponents(string: source.api) else { throw UZError.invalidURL }
        var items = components.queryItems ?? []
        items.removeAll { ["ac", "pg", "wd", "t", "ids", "id"].contains($0.name) }
        items.append(URLQueryItem(name: "ac", value: "list"))
        items.append(URLQueryItem(name: "pg", value: "1"))
        components.queryItems = items
        guard let url = components.url else { throw UZError.invalidURL }
        let data = try await request(url)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UZError.invalidResponse
        }
        return (root["class"] as? [[String: Any]] ?? []).compactMap(VideoCategory.init)
    }

    func detail(source: VideoSource, id: String) async throws -> VideoItem {
        guard var components = URLComponents(string: source.api) else { throw UZError.invalidURL }
        var items = components.queryItems ?? []
        items.removeAll { ["ac", "ids", "id", "pg", "wd", "t"].contains($0.name) }
        items.append(URLQueryItem(name: "ac", value: "detail"))
        items.append(URLQueryItem(name: "ids", value: id))
        components.queryItems = items
        guard let url = components.url else { throw UZError.invalidURL }
        let data = try await request(url)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let json = (root["list"] as? [[String: Any]])?.first else { throw UZError.invalidResponse }
        return VideoItem(json: json)
    }

    func doubanRecommendations(
        kind: RecommendationCatalogKind,
        start: Int,
        count: Int = 28,
        genre: String = "全部",
        region: String = "全部",
        year: String = "全部",
        platform: String = "全部",
        sort: String = "U"
    ) async throws -> DoubanRecommendationPage {
        let endpoint = kind == .movie ? "movie" : "tv"
        var components = URLComponents(string: "https://m.douban.com/rexxar/api/v2/\(endpoint)/recommend")!
        let typeValue: String
        let tags: String
        switch kind {
        case .movie:
            typeValue = genre
            tags = ""
        case .variety:
            typeValue = "综艺"
            tags = genre == "全部" ? "综艺" : "综艺,\(genre)"
        case .tv, .all:
            typeValue = "电视剧"
            tags = genre == "全部" ? "电视剧" : "电视剧,\(genre)"
        }
        let selected: [String: String] = ["类型": typeValue, "地区": region, "年代": year, "平台": platform]
        let selectedData = try JSONSerialization.data(withJSONObject: selected, options: [.sortedKeys])
        let selectedJSON = String(data: selectedData, encoding: .utf8) ?? "{}"
        components.queryItems = [
            URLQueryItem(name: "refresh", value: "0"),
            URLQueryItem(name: "start", value: String(max(0, start))),
            URLQueryItem(name: "count", value: String(max(1, count))),
            URLQueryItem(name: "selected_categories", value: selectedJSON),
            URLQueryItem(name: "uncollect", value: "false"),
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "tags", value: tags)
        ]
        guard let url = components.url else { throw UZError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("https://m.douban.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (AppleTV; CPU OS 18_2 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        let data = try await self.request(request)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawItems = root["items"] as? [[String: Any]] else { throw UZError.invalidResponse }
        return DoubanRecommendationPage(
            items: rawItems.map(DoubanRecommendation.init),
            total: Self.int(root["total"]) ?? rawItems.count,
            start: Self.int(root["start"]) ?? start
        )
    }

    private func request(_ url: URL) async throws -> Data {
        try await request(URLRequest(url: url))
    }

    private func request(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UZError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw UZError.server("视频源返回 HTTP \(http.statusCode)\(body.isEmpty ? "" : "：\(body)")")
        }
        return data
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}
