import Foundation

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var sources: [VideoSource] = []
    @Published var selectedSource: VideoSource?
    @Published var videos: [VideoItem] = []
    @Published var categories: [VideoCategory] = []
    @Published var selectedCategoryID: Int?
    @Published var isLoading = false
    @Published var loadingMessage = "正在加载…"
    @Published var errorMessage: String?
    @Published var subscriptionStatus = "尚未导入订阅"
    @Published private(set) var favorites: [VideoItem] = []
    @Published private(set) var history: [PlaybackRecord] = []
    @Published private(set) var recommendationShelves: [RecommendationCatalogKind: [DoubanRecommendation]] = [:]
    @Published private(set) var recommendationItems: [DoubanRecommendation] = []
    @Published private(set) var recommendationTotal = 0
    @Published private(set) var isRecommendationLoading = false
    @Published private(set) var recommendationProgress = "豆瓣完整推荐目录"
    @Published private(set) var isLoadingMoreVideos = false
    @Published private(set) var hasMoreVideos = false
    @Published private(set) var currentCatalogPage = 0

    private let sourcesKey = "uz.sources"
    private let selectedSourceKey = "uz.selectedSource"
    private let favoritesKey = "uz.favorites"
    private let historyKey = "uz.history"

    init() {
        loadSavedData()
    }

    func importShareCode(_ code: String) async {
        await perform(message: "正在导入视频源…") {
            let imported = try await UZAPI.shared.sources(shareCode: code)
            self.sources = imported
            self.recommendationShelves = [:]
            self.recommendationItems = []
            self.selectedSource = imported.first(where: { $0.name.localizedCaseInsensitiveContains("ikun") }) ?? imported.first
            self.selectedCategoryID = nil
            self.saveSources()
            try await self.loadCatalog()
        }
    }

    func importSubscriptionCode(_ code: String) async {
        await perform(message: "正在下载原站订阅…") {
            let data = try await UZAPI.shared.subscription(shareCode: code)
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try data.write(to: base.appendingPathComponent("uzAio.zip"), options: .atomic)
            self.subscriptionStatus = "原站订阅已下载（\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))）"
        }
    }

    func refresh(keyword: String? = nil) async {
        await perform(message: keyword == nil ? "正在刷新…" : "正在搜索…") {
            try await self.loadCatalog(keyword: keyword)
        }
    }

    func select(_ source: VideoSource) async {
        selectedSource = source
        selectedCategoryID = nil
        UserDefaults.standard.set(source.api, forKey: selectedSourceKey)
        await refresh()
    }

    func selectCategory(_ id: Int?) async {
        selectedCategoryID = id
        await refresh()
    }

    func fullDetail(for video: VideoItem) async -> VideoItem? {
        guard let selectedSource else {
            errorMessage = UZError.noSource.localizedDescription
            return nil
        }
        isLoading = true
        loadingMessage = "正在载入详情…"
        defer { isLoading = false }
        do {
            return try await UZAPI.shared.detail(source: selectedSource, id: video.id)
        } catch {
            // A number of MacCMS servers already include complete detail data in the list response.
            if !video.lines.isEmpty { return video }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func fullDetail(for video: VideoItem, source: VideoSource) async -> VideoItem? {
        isLoading = true
        loadingMessage = "正在从\(source.name)载入详情…"
        defer { isLoading = false }
        do {
            return try await UZAPI.shared.detail(source: source, id: video.id)
        } catch {
            if !video.lines.isEmpty { return video }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func loadRecommendationShelves(force: Bool = false) async {
        if !force, !recommendationShelves.isEmpty { return }
        isRecommendationLoading = true
        recommendationProgress = "正在加载豆瓣完整推荐…"
        defer { isRecommendationLoading = false }
        await withTaskGroup(of: (RecommendationCatalogKind, [DoubanRecommendation]).self) { group in
            for kind in [RecommendationCatalogKind.movie, .tv, .variety] {
                group.addTask {
                    let page = try? await UZAPI.shared.doubanRecommendations(kind: kind, start: 0, count: 18)
                    return (kind, page?.items ?? [])
                }
            }
            var loaded: [RecommendationCatalogKind: [DoubanRecommendation]] = [:]
            for await result in group { loaded[result.0] = result.1 }
            recommendationShelves = loaded
        }
        let count = recommendationShelves.values.reduce(0) { $0 + $1.count }
        recommendationProgress = count > 0 ? "豆瓣完整目录 · 选择影片后搜索全部 \(sources.count) 个源" : "推荐目录暂时无法连接"
    }

    func loadRecommendations(
        kind: RecommendationCatalogKind,
        genre: String,
        region: String,
        year: String,
        platform: String,
        sort: String,
        reset: Bool
    ) async {
        guard !isRecommendationLoading else { return }
        isRecommendationLoading = true
        if reset {
            recommendationItems = []
            recommendationTotal = 0
        }
        let start = reset ? 0 : recommendationItems.count
        recommendationProgress = start == 0 ? "正在加载完整推荐目录…" : "正在继续加载…"
        defer { isRecommendationLoading = false }
        do {
            let page = try await UZAPI.shared.doubanRecommendations(
                kind: kind, start: start, count: 28, genre: genre,
                region: region, year: year, platform: platform, sort: sort
            )
            if reset {
                recommendationItems = page.items
            } else {
                let existing = Set(recommendationItems.map(\.id))
                recommendationItems.append(contentsOf: page.items.filter { !existing.contains($0.id) })
            }
            recommendationTotal = page.total
            recommendationProgress = "已加载 \(recommendationItems.count)/\(page.total) · 播放时搜索全部 \(sources.count) 个源"
        } catch {
            recommendationProgress = "推荐目录加载失败：\(error.localizedDescription)"
        }
    }

    func searchAllSources(
        keyword: String,
        onUpdate: ([RecommendationItem], Int, Int) -> Void
    ) async -> [RecommendationItem] {
        var sourceList = sources
        guard !sourceList.isEmpty else { return [] }
        // The currently selected source is the one the user already trusts and
        // is most likely to be responsive, so always search it first.
        if let selectedSource,
           let index = sourceList.firstIndex(where: { $0.id == selectedSource.id }) {
            sourceList.insert(sourceList.remove(at: index), at: 0)
        }
        var iterator = sourceList.makeIterator()
        var matches: [RecommendationItem] = []
        var completed = 0
        await withTaskGroup(of: RecommendationSourceResult?.self) { group in
            func enqueue(_ source: VideoSource) {
                group.addTask {
                    await Self.search(source: source, keyword: keyword, timeoutSeconds: 6)
                }
            }
            for _ in 0..<min(24, sourceList.count) {
                if let source = iterator.next() { enqueue(source) }
            }
            while let result = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                completed += 1
                if let result {
                    matches.append(contentsOf: result.videos.map { RecommendationItem(source: result.source, video: $0) })
                }
                matches = Self.sortedSearchMatches(matches, keyword: keyword)
                onUpdate(matches, completed, sourceList.count)
                if let source = iterator.next() { enqueue(source) }
            }
        }
        return Self.sortedSearchMatches(matches, keyword: keyword)
    }

    private nonisolated static func search(
        source: VideoSource,
        keyword: String,
        timeoutSeconds: Double
    ) async -> RecommendationSourceResult? {
        await withTaskGroup(of: RecommendationSourceResult?.self) { group in
            group.addTask {
                guard let page = try? await UZAPI.shared.catalog(source: source, keyword: keyword, page: 1) else {
                    return nil
                }
                return RecommendationSourceResult(source: source, videos: page.videos)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private nonisolated static func sortedSearchMatches(
        _ matches: [RecommendationItem],
        keyword: String
    ) -> [RecommendationItem] {
        let normalizedKeyword = normalizedTitle(keyword)
        return matches.sorted { left, right in
            let leftExact = Self.normalizedTitle(left.video.name) == normalizedKeyword
            let rightExact = Self.normalizedTitle(right.video.name) == normalizedKeyword
            if leftExact != rightExact { return leftExact }
            let leftPlayable = left.video.preferredLine != nil
            let rightPlayable = right.video.preferredLine != nil
            if leftPlayable != rightPlayable { return leftPlayable }
            return (left.video.score ?? 0) > (right.video.score ?? 0)
        }
    }

    func toggleFavorite(_ video: VideoItem) {
        if let index = favorites.firstIndex(where: { $0.id == video.id }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(video, at: 0)
        }
        persist(favorites, key: favoritesKey)
    }

    func isFavorite(_ video: VideoItem) -> Bool {
        favorites.contains(where: { $0.id == video.id })
    }

    func recordPlayback(
        video: VideoItem,
        episode: Episode,
        progressSeconds: Double = 0,
        durationSeconds: Double? = nil
    ) {
        history.removeAll { $0.video.id == video.id }
        history.insert(
            PlaybackRecord(
                video: video,
                episodeTitle: episode.title,
                episodeURL: episode.url.absoluteString,
                lineIndex: episode.lineIndex,
                progressSeconds: max(0, progressSeconds),
                durationSeconds: durationSeconds,
                playedAt: Date()
            ),
            at: 0
        )
        if history.count > 100 { history.removeLast(history.count - 100) }
        persist(history, key: historyKey)
    }

    func playbackRecord(for video: VideoItem) -> PlaybackRecord? {
        history.first(where: { $0.video.id == video.id })
    }

    func removeSource(_ source: VideoSource) {
        sources.removeAll { $0.id == source.id }
        if selectedSource?.id == source.id { selectedSource = sources.first }
        saveSources()
    }

    func clearHistory() {
        history = []
        persist(history, key: historyKey)
    }

    func loadMoreVideos() async {
        guard hasMoreVideos, !isLoadingMoreVideos, let selectedSource else { return }
        isLoadingMoreVideos = true
        defer { isLoadingMoreVideos = false }
        do {
            let nextPage = currentCatalogPage + 1
            let page = try await UZAPI.shared.catalog(source: selectedSource, categoryID: selectedCategoryID, page: nextPage)
            let existing = Set(videos.map(\.id))
            let additions = page.videos.filter { !existing.contains($0.id) }
            videos.append(contentsOf: additions)
            currentCatalogPage = page.page
            hasMoreVideos = page.hasMore && !page.videos.isEmpty && !additions.isEmpty
        } catch {
            errorMessage = "下一页加载失败：\(error.localizedDescription)"
        }
    }

    private func loadCatalog(keyword: String? = nil) async throws {
        guard let selectedSource else { throw UZError.noSource }
        let page = try await UZAPI.shared.catalog(source: selectedSource, categoryID: selectedCategoryID, keyword: keyword, page: 1)
        videos = page.videos
        currentCatalogPage = page.page
        hasMoreVideos = keyword == nil && page.hasMore
        if !page.categories.isEmpty { categories = page.categories }
    }

    private func perform(message: String, operation: () async throws -> Void) async {
        isLoading = true
        loadingMessage = message
        errorMessage = nil
        defer { isLoading = false }
        do { try await operation() } catch { errorMessage = error.localizedDescription }
    }

    private nonisolated static func normalizedTitle(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "[^\\p{L}\\p{N}]", with: "", options: .regularExpression)
    }

    private func saveSources() {
        persist(sources, key: sourcesKey)
        UserDefaults.standard.set(selectedSource?.api, forKey: selectedSourceKey)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func loadSavedData() {
        sources = decode([VideoSource].self, key: sourcesKey) ?? []
        favorites = decode([VideoItem].self, key: favoritesKey) ?? []
        history = decode([PlaybackRecord].self, key: historyKey) ?? []
        let savedAPI = UserDefaults.standard.string(forKey: selectedSourceKey)
        selectedSource = sources.first(where: { $0.api == savedAPI }) ?? sources.first
        if ProcessInfo.processInfo.arguments.contains("-UITesting") {
            selectedSource = sources.first(where: { $0.name.localizedCaseInsensitiveContains("ikun") }) ?? selectedSource
        }
        if selectedSource != nil {
            Task { await refresh() }
        } else {
            // The original project uses 1111 as its built-in public source share code.
            Task { await importShareCode("1111") }
        }
    }
}

private struct RecommendationSourceResult: Sendable {
    let source: VideoSource
    let videos: [VideoItem]
}
