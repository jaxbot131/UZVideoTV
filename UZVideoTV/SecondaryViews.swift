import SwiftUI

struct DetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let video: VideoItem
    let resumeRecord: PlaybackRecord?
    @State private var selectedLineID: Int
    @State private var playing: Episode?
    @State private var pendingResumeSeconds: Double
    @FocusState private var focusedEpisodeID: String?

    init(video: VideoItem, resumeRecord: PlaybackRecord? = nil) {
        self.video = video
        self.resumeRecord = resumeRecord
        let resumedEpisode = Self.episode(in: video, matching: resumeRecord)
        _selectedLineID = State(initialValue: resumedEpisode?.lineIndex ?? video.preferredLine?.id ?? 0)
        _playing = State(initialValue: resumedEpisode)
        _pendingResumeSeconds = State(initialValue: resumedEpisode == nil ? 0 : (resumeRecord?.progressSeconds ?? 0))
    }

    private var selectedLine: PlayLine? {
        video.lines.first(where: { $0.id == selectedLineID }) ?? video.preferredLine
    }

    var body: some View {
        Group {
            if let playing {
                PlayerScreen(
                    video: video,
                    episode: playing,
                    initialPosition: pendingResumeSeconds,
                    previousEpisode: adjacentEpisode(to: playing, offset: -1),
                    nextEpisode: adjacentEpisode(to: playing, offset: 1),
                    onChangeEpisode: startPlayback
                ) { self.playing = nil }
                .id(playing.id)
            } else {
                detailContent
            }
        }
        .onExitCommand {
            if playing != nil { playing = nil } else { dismiss() }
        }
    }

    private var detailContent: some View {
        ZStack {
            UZTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HStack(alignment: .top, spacing: 44) {
                        AsyncImage(url: video.posterURL) { phase in
                            if case .success(let image) = phase { image.resizable().scaledToFill() }
                            else { Color.gray.opacity(0.18).overlay(Image(systemName: "film").font(.system(size: 54))) }
                        }
                        .frame(width: 270, height: 380).clipShape(RoundedRectangle(cornerRadius: 14))

                        VStack(alignment: .leading, spacing: 18) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(video.name).font(.system(size: 43, weight: .bold)).foregroundStyle(UZTheme.text)
                                    Text([video.year, video.area, video.typeName, video.remarks].filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.title3).foregroundStyle(UZTheme.secondaryText)
                                }
                                Spacer()
                                Button { store.toggleFavorite(video) } label: {
                                    Label(store.isFavorite(video) ? "已收藏" : "收藏", systemImage: store.isFavorite(video) ? "heart.fill" : "heart")
                                }
                                Button("返回", systemImage: "chevron.backward") { dismiss() }
                            }
                            if !video.actor.isEmpty { Text("主演：\(video.actor)").lineLimit(2).foregroundStyle(UZTheme.text) }
                            if !video.director.isEmpty { Text("导演：\(video.director)").lineLimit(1).foregroundStyle(UZTheme.text) }
                            Text(video.cleanSummary.isEmpty ? "暂无简介" : video.cleanSummary)
                                .font(.body).foregroundStyle(UZTheme.secondaryText).lineLimit(6)
                        }
                    }

                    if video.lines.isEmpty {
                        ContentUnavailableView("暂无播放地址", systemImage: "exclamationmark.triangle", description: Text("可以返回并切换其他视频源搜索同一影片"))
                    } else {
                        HStack(spacing: 16) {
                            Text("播放线路").font(.title2.bold()).foregroundStyle(UZTheme.text)
                            ForEach(video.lines) { line in
                                Button(lineLabel(line)) {
                                    selectedLineID = line.id
                                    focusedEpisodeID = line.episodes.first?.id
                                }
                                    .buttonStyle(LineButtonStyle(selected: line.id == selectedLineID))
                                    .accessibilityIdentifier("line-\(line.id)")
                            }
                        }
                        .focusSection()
                        Text("选集").font(.title2.bold()).foregroundStyle(UZTheme.text)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 18)], spacing: 18) {
                            ForEach(selectedLine?.episodes ?? []) { episode in
                                Button(episode.title) {
                                    store.recordPlayback(video: video, episode: episode)
                                    playing = episode
                                }
                                .buttonStyle(EpisodeButtonStyle())
                                .focused($focusedEpisodeID, equals: episode.id)
                                .accessibilityIdentifier("episode-\(episode.id)")
                            }
                        }
                        .focusSection()
                    }
                }
                .padding(.horizontal, 58).padding(.vertical, 38)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                focusedEpisodeID = selectedLine?.episodes.first?.id
            }
        }
    }

    private func lineLabel(_ line: PlayLine) -> String {
        line.episodes.contains(where: { $0.isDirectStream }) ? "\(line.name) · 直链" : line.name
    }

    private func adjacentEpisode(to episode: Episode, offset: Int) -> Episode? {
        guard let line = video.lines.first(where: { $0.id == episode.lineIndex }),
              let index = line.episodes.firstIndex(of: episode) else { return nil }
        let target = index + offset
        guard line.episodes.indices.contains(target) else { return nil }
        return line.episodes[target]
    }

    private func startPlayback(_ episode: Episode) {
        pendingResumeSeconds = 0
        store.recordPlayback(video: video, episode: episode)
        playing = episode
    }

    private static func episode(in video: VideoItem, matching record: PlaybackRecord?) -> Episode? {
        guard let record else { return nil }
        let episodes = video.lines.flatMap(\.episodes)
        if let episodeURL = record.episodeURL,
           let exact = episodes.first(where: { $0.url.absoluteString == episodeURL }) {
            return exact
        }
        if let lineIndex = record.lineIndex,
           let sameLine = episodes.first(where: { $0.lineIndex == lineIndex && $0.title == record.episodeTitle }) {
            return sameLine
        }
        return episodes.first(where: { $0.title == record.episodeTitle })
    }
}

struct SourcePickerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focusedSourceID: String?

    private var filteredSources: [VideoSource] {
        guard !query.isEmpty else { return store.sources }
        return store.sources.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.api.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ZStack {
            UZTheme.background.ignoresSafeArea()
            VStack(spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("视频源").font(.largeTitle.bold()).foregroundStyle(UZTheme.text)
                        Text("分享码 1111 共 \(store.sources.count) 个视频源").foregroundStyle(UZTheme.secondaryText)
                    }
                    Spacer()
                    TextField("搜索视频源", text: $query).frame(width: 520)
                    Button("返回", systemImage: "chevron.backward") { dismiss() }
                }

                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(filteredSources) { source in
                            Button {
                                Task {
                                    await store.select(source)
                                    dismiss()
                                }
                            } label: {
                                HStack(spacing: 16) {
                                    Circle().fill(UZTheme.blue).frame(width: 15, height: 15)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(source.name).font(.title3.bold()).foregroundStyle(UZTheme.text)
                                        Text(source.api).font(.caption).foregroundStyle(UZTheme.secondaryText).lineLimit(1)
                                    }
                                    Spacer()
                                    if source.id == store.selectedSource?.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(UZTheme.blue)
                                    }
                                }
                                .padding(.horizontal, 22).frame(height: 78)
                            }
                            .buttonStyle(SourceListButtonStyle())
                            .focused($focusedSourceID, equals: source.id)
                            .accessibilityIdentifier("source-\(source.id)")
                        }
                    }
                    .padding(18)
                }
            }
            .padding(48)
        }
        .onAppear { focusedSourceID = store.selectedSource?.id ?? store.sources.first?.id }
        .onExitCommand { dismiss() }
    }
}

private struct SourceListButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isFocused ? Color.white : UZTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isFocused ? UZTheme.blue : UZTheme.border, lineWidth: isFocused ? 4 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.18 : 0), radius: 13, y: 5)
            .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.025 : 1))
    }
}

private struct LineButtonStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline).padding(.horizontal, 22).padding(.vertical, 12)
            .foregroundStyle(isFocused ? UZTheme.blue : (selected ? Color.white : UZTheme.text))
            .background(isFocused ? Color.white : (selected ? UZTheme.blue : UZTheme.surface), in: Capsule())
            .overlay(Capsule().stroke(isFocused ? UZTheme.blue : UZTheme.border, lineWidth: isFocused ? 4 : 1))
            .scaleEffect(isFocused ? 1.08 : 1)
    }
}

private struct EpisodeButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline).lineLimit(1)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .foregroundStyle(isFocused ? Color.white : UZTheme.text)
            .background(isFocused ? UZTheme.blue : UZTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isFocused ? Color.white : UZTheme.border, lineWidth: isFocused ? 3 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.2 : 0.05), radius: 10, y: 4)
            .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? 1.05 : 1))
    }
}

struct SearchView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var selectedVideo: VideoItem?
    @FocusState private var searchFocus: SearchFocus?

    var body: some View {
        ZStack {
            UZTheme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                HStack {
                    Text("搜索").font(.largeTitle.bold()).foregroundStyle(UZTheme.text)
                    Spacer()
                    Button("关闭", systemImage: "xmark") { dismiss() }
                        .buttonStyle(SearchActionButtonStyle())
                        .focused($searchFocus, equals: .close)
                }
                HStack(spacing: 18) {
                    TextField("", text: $keyword, prompt: Text("输入片名").foregroundStyle(UZTheme.secondaryText))
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .foregroundStyle(UZTheme.text)
                        .tint(UZTheme.blue)
                        .padding(.horizontal, 22)
                        .frame(height: 66)
                        .background(UZTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(searchFocus == .field ? UZTheme.blue : UZTheme.border, lineWidth: searchFocus == .field ? 5 : 1))
                        .focused($searchFocus, equals: .field)
                        .accessibilityIdentifier("search-field")
                        .onSubmit { Task { await store.refresh(keyword: keyword) } }
                    Button("搜索", systemImage: "magnifyingglass") { Task { await store.refresh(keyword: keyword) } }
                        .buttonStyle(SearchActionButtonStyle())
                        .focused($searchFocus, equals: .search)
                        .accessibilityIdentifier("search-submit")
                }
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.videos) { item in
                            Button { open(item) } label: {
                                HStack(spacing: 20) {
                                    AsyncImage(url: item.posterURL) { image in image.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.3) }
                                        .frame(width: 76, height: 102).clipShape(RoundedRectangle(cornerRadius: 8))
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(item.name).font(.title3.bold()).foregroundStyle(UZTheme.text)
                                        Text(item.remarks.isEmpty ? "暂无更新信息" : item.remarks)
                                            .font(.callout).foregroundStyle(UZTheme.secondaryText)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(UZTheme.text)
                                }
                                .padding(.horizontal, 20).frame(height: 118)
                            }
                            .buttonStyle(SearchResultButtonStyle())
                            .focused($searchFocus, equals: .result(item.id))
                            .accessibilityIdentifier("search-result-\(item.id)")
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 10)
                }
            }
            .padding(54)
            .defaultFocus($searchFocus, .field)
        }
        .fullScreenCover(item: $selectedVideo) { DetailView(video: $0) }
    }

    private func open(_ item: VideoItem) {
        Task { if let detail = await store.fullDetail(for: item) { selectedVideo = detail } }
    }
}

private enum SearchFocus: Hashable {
    case field
    case search
    case close
    case result(String)
}

private struct SearchActionButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isFocused ? Color.white : UZTheme.text)
            .padding(.horizontal, 22).frame(height: 62)
            .background(isFocused ? UZTheme.blue : UZTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isFocused ? Color.white : UZTheme.border, lineWidth: isFocused ? 3 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.24 : 0.08), radius: 12, y: 5)
            .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.07 : 1))
    }
}

private struct SearchResultButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isFocused ? Color.white : UZTheme.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isFocused ? UZTheme.blue : UZTheme.border, lineWidth: isFocused ? 5 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.22 : 0.06), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.985 : (isFocused ? 1.018 : 1))
    }
}

struct CollectionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var showCloseButton = false
    @State private var showingHistory = false
    @State private var selection: CollectionSelection?

    init(showCloseButton: Bool = false, initiallyShowingHistory: Bool = false) {
        self.showCloseButton = showCloseButton
        _showingHistory = State(initialValue: initiallyShowingHistory)
    }

    private var isEmpty: Bool { showingHistory ? store.history.isEmpty : store.favorites.isEmpty }

    var body: some View {
        ZStack {
            UZTheme.background.ignoresSafeArea()
            VStack(spacing: 22) {
                HStack {
                    Button("收藏列表") { showingHistory = false }.buttonStyle(LineButtonStyle(selected: !showingHistory))
                    Button("播放记录") { showingHistory = true }.buttonStyle(LineButtonStyle(selected: showingHistory))
                    Spacer()
                    if showingHistory && !store.history.isEmpty { Button("清空记录", systemImage: "trash") { store.clearHistory() } }
                    if showCloseButton { Button("返回", systemImage: "chevron.backward") { dismiss() } }
                }
                if isEmpty {
                    ContentUnavailableView(showingHistory ? "没有播放记录" : "没有收藏", systemImage: showingHistory ? "clock" : "heart", description: Text("从影片详情页开始播放或添加收藏"))
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(250), spacing: 26), count: 6), spacing: 32) {
                            if showingHistory {
                                ForEach(store.history) { record in
                                    Button {
                                        selection = CollectionSelection(video: record.video, resumeRecord: record)
                                    } label: {
                                        HistoryPosterCard(record: record)
                                    }
                                    .buttonStyle(PosterFocusStyle())
                                }
                            } else {
                                ForEach(store.favorites) { item in
                                    Button {
                                        selection = CollectionSelection(video: item, resumeRecord: nil)
                                    } label: {
                                        PosterCard(video: item)
                                    }
                                    .buttonStyle(PosterFocusStyle())
                                }
                            }
                        }
                    }
                }
            }
            .padding(48)
        }
        .fullScreenCover(item: $selection) {
            DetailView(video: $0.video, resumeRecord: $0.resumeRecord)
        }
    }
}

private struct CollectionSelection: Identifiable {
    let video: VideoItem
    let resumeRecord: PlaybackRecord?
    var id: String { "\(video.id)|\(resumeRecord?.playedAt.timeIntervalSince1970 ?? 0)" }
}

private struct HistoryPosterCard: View {
    let record: PlaybackRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterCard(video: record.video)
            Text("看到：\(record.episodeTitle)")
                .font(.subheadline.bold())
                .foregroundStyle(UZTheme.text)
                .lineLimit(1)
            ProgressView(value: record.progress)
                .tint(UZTheme.blue)
            Text(progressText)
                .font(.caption)
                .foregroundStyle(UZTheme.secondaryText)
        }
        .frame(width: 250, alignment: .leading)
    }

    private var progressText: String {
        let current = timeText(record.progressSeconds ?? 0)
        guard let duration = record.durationSeconds, duration > 0 else { return "已播放 \(current)" }
        return "\(current) / \(timeText(duration)) · \(Int(record.progress * 100))%"
    }

    private func timeText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct RecommendView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedRecommendation: DoubanRecommendation?
    @State private var kind: RecommendationCatalogKind = .all
    @State private var selectedGenre = "全部"
    @State private var selectedRegion = "全部"
    @State private var selectedYear = "全部"
    @State private var selectedPlatform = "全部"
    @State private var selectedSort = "近期热度"

    private let gridColumns = Array(repeating: GridItem(.fixed(220), spacing: 22), count: 7)

    var body: some View {
        ZStack {
            UZTheme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                recommendationHeader
                if kind == .all {
                    recommendationShelves
                } else {
                    filterPanel
                    recommendationGrid
                }
            }
            .padding(.horizontal, 38)
            .padding(.top, 16)
        }
        .task { await store.loadRecommendationShelves() }
        .task(id: filterKey) {
            guard kind != .all else { return }
            await store.loadRecommendations(
                kind: kind, genre: selectedGenre, region: selectedRegion,
                year: selectedYear, platform: selectedPlatform,
                sort: sortCode, reset: true
            )
        }
        .fullScreenCover(item: $selectedRecommendation) { AllSourceSearchView(recommendation: $0) }
    }

    private var recommendationHeader: some View {
        HStack(spacing: 16) {
            ForEach(RecommendationCatalogKind.allCases) { item in
                Button(item.title) {
                    kind = item
                    resetFilters()
                }
                .buttonStyle(RecommendationTabStyle(selected: kind == item))
                .accessibilityIdentifier("recommend-tab-\(item.rawValue)")
            }
            Spacer()
            if store.isRecommendationLoading {
                ProgressView().scaleEffect(0.8)
            }
            Text(store.recommendationProgress)
                .font(.callout.bold())
                .foregroundStyle(UZTheme.secondaryText)
                .accessibilityIdentifier("recommend-status")
            Button {
                Task {
                    if kind == .all {
                        await store.loadRecommendationShelves(force: true)
                    } else {
                        await store.loadRecommendations(
                            kind: kind, genre: selectedGenre, region: selectedRegion,
                            year: selectedYear, platform: selectedPlatform,
                            sort: sortCode, reset: true
                        )
                    }
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(HeaderButtonStyle())
            .disabled(store.isRecommendationLoading)
            .accessibilityLabel("刷新完整推荐目录")
        }
        .frame(height: 62)
        .focusSection()
    }

    private var recommendationShelves: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                recommendationShelf(title: "豆瓣热门电影", items: store.recommendationShelves[.movie] ?? [])
                recommendationShelf(title: "豆瓣热门电视剧", items: store.recommendationShelves[.tv] ?? [])
                recommendationShelf(title: "豆瓣热门综艺", items: store.recommendationShelves[.variety] ?? [])
            }
            .padding(.bottom, 36)
        }
    }

    private func recommendationShelf(title: String, items: [DoubanRecommendation]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(title).font(.title3.bold()).foregroundStyle(UZTheme.text)
                Text("\(items.count)").font(.caption.bold()).foregroundStyle(UZTheme.blue)
            }
            if items.isEmpty && store.isRecommendationLoading {
                RoundedRectangle(cornerRadius: 14)
                    .fill(UZTheme.surface)
                    .frame(height: 130)
                    .overlay(Text("正在载入豆瓣完整目录…").foregroundStyle(UZTheme.secondaryText))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(items) { item in
                            recommendationButton(item, compact: true)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .focusSection()
            }
        }
    }

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            recommendationFilterRow(title: "类型", values: genreOptions, selection: $selectedGenre)
            recommendationFilterRow(title: "地区", values: regionOptions, selection: $selectedRegion)
            recommendationFilterRow(title: "年代", values: yearOptions, selection: $selectedYear)
            recommendationFilterRow(title: "平台", values: platformOptions, selection: $selectedPlatform)
            recommendationFilterRow(title: "排序", values: sortOptions, selection: $selectedSort)
        }
        .padding(.vertical, 4)
    }

    private func recommendationFilterRow(title: String, values: [String], selection: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline.bold())
                .foregroundStyle(.white)
                .frame(width: 76, height: 40)
                .background(UZTheme.blue, in: RoundedRectangle(cornerRadius: 9))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(values, id: \.self) { value in
                        Button(value) { selection.wrappedValue = value }
                            .buttonStyle(RecommendationChipStyle(selected: selection.wrappedValue == value))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .focusSection()
        }
        .frame(height: 49)
        .accessibilityIdentifier("recommend-filter-\(title)")
    }

    private var recommendationGrid: some View {
        Group {
            if store.recommendationItems.isEmpty && !store.isRecommendationLoading {
                ContentUnavailableView("没有符合条件的影片", systemImage: "line.3.horizontal.decrease.circle", description: Text("可减少筛选条件，或刷新推荐目录"))
                    .foregroundStyle(UZTheme.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: 25) {
                        ForEach(store.recommendationItems) { item in
                            recommendationButton(item, compact: false)
                        }
                        if store.recommendationItems.count < store.recommendationTotal {
                            Button {
                                loadMore()
                            } label: {
                                VStack(spacing: 16) {
                                    if store.isRecommendationLoading { ProgressView() }
                                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 52))
                                    Text("加载更多").font(.headline.bold())
                                    Text("\(store.recommendationItems.count)/\(store.recommendationTotal)").font(.caption)
                                }
                                .foregroundStyle(UZTheme.blue)
                                .frame(width: 220, height: 310)
                                .background(UZTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(PosterFocusStyle())
                            .disabled(store.isRecommendationLoading)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 38)
                }
            }
        }
    }

    private func recommendationButton(_ item: DoubanRecommendation, compact: Bool) -> some View {
        Button { open(item) } label: {
            RecommendationPosterCard(item: item, compact: compact)
        }
        .buttonStyle(PosterFocusStyle())
        .accessibilityIdentifier("recommend-poster-\(item.id.hashValue)")
    }

    private var genreOptions: [String] {
        switch kind {
        case .tv: return ["全部", "喜剧", "爱情", "悬疑", "动画", "武侠", "古装", "家庭", "犯罪", "科幻", "恐怖", "历史", "战争", "动作", "冒险", "奇幻"]
        case .movie: return ["全部", "喜剧", "爱情", "动作", "科幻", "动画", "悬疑", "犯罪", "惊悚", "冒险", "音乐", "历史", "奇幻", "恐怖", "战争", "传记", "歌舞", "武侠", "灾难"]
        case .variety: return ["全部", "真人秀", "脱口秀", "音乐", "歌舞"]
        case .all: return ["全部"]
        }
    }

    private let regionOptions = ["全部", "华语", "欧美", "国外", "韩国", "日本", "中国大陆", "中国香港", "美国", "英国", "泰国", "中国台湾", "意大利", "法国", "德国", "西班牙", "俄罗斯", "加拿大", "印度"]
    private let yearOptions = ["全部", "2020年代", "2026", "2025", "2024", "2023", "2022", "2021", "2020", "2019", "2010年代", "2000年代", "90年代", "80年代", "70年代", "60年代", "更早"]
    private let platformOptions = ["全部", "腾讯视频", "爱奇艺", "优酷", "湖南卫视", "Netflix", "HBO", "BBC", "NHK", "CBS", "NBC", "tvN"]
    private let sortOptions = ["近期热度", "综合排序", "首播时间", "高分优先"]

    private func resetFilters() {
        selectedGenre = "全部"
        selectedRegion = "全部"
        selectedYear = "全部"
        selectedPlatform = "全部"
        selectedSort = "近期热度"
    }

    private var sortCode: String {
        ["综合排序": "T", "近期热度": "U", "首播时间": "R", "高分优先": "S"][selectedSort] ?? "U"
    }

    private var filterKey: String {
        [kind.rawValue, selectedGenre, selectedRegion, selectedYear, selectedPlatform, selectedSort].joined(separator: "|")
    }

    private func loadMore() {
        Task {
            await store.loadRecommendations(
                kind: kind, genre: selectedGenre, region: selectedRegion,
                year: selectedYear, platform: selectedPlatform,
                sort: sortCode, reset: false
            )
        }
    }

    private func open(_ item: DoubanRecommendation) {
        selectedRecommendation = item
    }
}

private extension RecommendationCatalogKind {
    var title: String {
        switch self {
        case .all: return "推荐"
        case .tv: return "找电视剧"
        case .movie: return "找电影"
        case .variety: return "找综艺"
        }
    }

}

private struct RecommendationTabStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.bold())
            .foregroundStyle(isFocused || selected ? UZTheme.blue : UZTheme.text)
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(isFocused ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottom) {
                Capsule().fill(isFocused || selected ? UZTheme.blue : .clear).frame(height: 4)
            }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isFocused ? UZTheme.blue : .clear, lineWidth: 3))
            .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.06 : 1))
    }
}

private struct RecommendationChipStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.bold())
            .foregroundStyle(isFocused ? UZTheme.blue : (selected ? Color.white : UZTheme.text))
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(isFocused ? Color.white : (selected ? UZTheme.blue : Color.clear), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(isFocused ? UZTheme.blue : (selected ? UZTheme.blue : UZTheme.border), lineWidth: isFocused ? 3 : 1))
            .scaleEffect(configuration.isPressed ? 0.94 : (isFocused ? 1.08 : 1))
    }
}

private struct RecommendationPosterCard: View {
    let item: DoubanRecommendation
    let compact: Bool

    private var width: CGFloat { compact ? 190 : 220 }
    private var height: CGFloat { compact ? 270 : 310 }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomTrailing) {
                DoubanRemoteImage(url: item.posterURL)
                .frame(width: width, height: height)
                .clipped()
                VStack(alignment: .trailing, spacing: 5) {
                    if let score = item.score, score > 0 {
                        Label(String(format: "%.1f", score), systemImage: "star.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(UZTheme.text)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Color.white.opacity(0.90), in: RoundedRectangle(cornerRadius: 6))
                    }
                    Text("豆瓣")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(UZTheme.blue.opacity(0.92), in: RoundedRectangle(cornerRadius: 6))
                }
                .padding(7)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(item.title)
                .font(compact ? .callout.bold() : .headline)
                .foregroundStyle(UZTheme.text)
                .lineLimit(1)
            Text([item.year, item.score.map { String(format: "豆瓣 %.1f", $0) } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(UZTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
    }
}

private struct DoubanRemoteImage: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Color.gray.opacity(0.18), Color.gray.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                    ProgressView().scaleEffect(0.7)
                    Image(systemName: "film").font(.system(size: 38)).foregroundStyle(UZTheme.secondaryText.opacity(0.45))
                }
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        var request = URLRequest(url: url)
        request.setValue("https://m.douban.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (AppleTV; CPU OS 18_2 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let loaded = UIImage(data: data) else { return }
        image = loaded
    }
}

struct AllSourceSearchView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let recommendation: DoubanRecommendation
    @State private var matches: [RecommendationItem] = []
    @State private var isSearching = true
    @State private var searchedSourceCount = 0
    @State private var selectedVideo: VideoItem?

    private let columns = Array(repeating: GridItem(.fixed(250), spacing: 26), count: 6)

    var body: some View {
        ZStack {
            UZTheme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(recommendation.title).font(.largeTitle.bold()).foregroundStyle(UZTheme.text)
                        Text(searchStatus)
                            .foregroundStyle(UZTheme.secondaryText)
                    }
                    Spacer()
                    if isSearching { ProgressView().scaleEffect(0.9) }
                    Button("返回", systemImage: "chevron.backward") { dismiss() }
                }
                if matches.isEmpty && !isSearching {
                    ContentUnavailableView("全部视频源都没有找到", systemImage: "magnifyingglass", description: Text("可以稍后重试，或回到首页手动搜索影片名称"))
                        .foregroundStyle(UZTheme.text)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 32) {
                            ForEach(matches) { item in
                                Button { open(item) } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        PosterCard(video: item.video)
                                        Text(item.source.name)
                                            .font(.caption.bold()).foregroundStyle(.white)
                                            .padding(.horizontal, 9).padding(.vertical, 5)
                                            .background(UZTheme.blue, in: Capsule())
                                    }
                                }
                                .buttonStyle(PosterFocusStyle())
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .padding(46)
        }
        .task {
            matches = await store.searchAllSources(keyword: recommendation.title) { updated, completed, _ in
                matches = updated
                searchedSourceCount = completed
            }
            isSearching = false
        }
        .fullScreenCover(item: $selectedVideo) { DetailView(video: $0) }
    }

    private func open(_ item: RecommendationItem) {
        Task { selectedVideo = await store.fullDetail(for: item.video, source: item.source) }
    }

    private var searchStatus: String {
        if isSearching {
            if matches.isEmpty {
                return "正在快速搜索视频源 · \(searchedSourceCount)/\(store.sources.count)"
            }
            return "已找到 \(matches.count) 个结果，可立即选择 · 后台继续搜索 \(searchedSourceCount)/\(store.sources.count)"
        }
        return "搜索完成 · 找到 \(matches.count) 个结果"
    }
}

struct PlaceholderSection: View {
    let title: String
    let icon: String
    let detail: String
    var body: some View {
        ZStack {
            UZTheme.background.ignoresSafeArea()
            ContentUnavailableView(title, systemImage: icon, description: Text(detail))
                .foregroundStyle(UZTheme.text)
        }
    }
}

struct SettingsView: View {
    let focusRequest: Int
    let onRequestBottomFocus: () -> Void
    @State private var destination: SettingsDestination?
    @FocusState private var focusedDestination: SettingsDestination?
    @FocusState private var bottomExitFocused: Bool

    init(focusRequest: Int = 0, onRequestBottomFocus: @escaping () -> Void = {}) {
        self.focusRequest = focusRequest
        self.onRequestBottomFocus = onRequestBottomFocus
    }

    var body: some View {
        NavigationStack {
            ZStack {
                UZTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    Text("设置").font(.largeTitle.bold()).foregroundStyle(UZTheme.text).padding(.bottom, 24)
                    SettingsRow(title: "数据管理", icon: "externaldrive") { destination = .data }
                        .focused($focusedDestination, equals: .data)
                        .accessibilityIdentifier("settings-data")
                    SettingsRow(title: "功能设置", icon: "switch.2") { destination = .features }
                        .focused($focusedDestination, equals: .features)
                    SettingsRow(title: "播放设置", icon: "play.rectangle") { destination = .playback }
                        .focused($focusedDestination, equals: .playback)
                    SettingsRow(title: "界面/语言", icon: "character.bubble") { destination = .appearance }
                        .focused($focusedDestination, equals: .appearance)
                    SettingsRow(title: "扩展调试", subtitle: "用于开发扩展时快速调试", icon: "ladybug") { destination = .debug }
                        .focused($focusedDestination, equals: .debug)
                    SettingsRow(title: "工具箱", icon: "wrench.and.screwdriver") { destination = .tools }
                        .focused($focusedDestination, equals: .tools)
                        .onMoveCommand { if $0 == .down { onRequestBottomFocus() } }
                    Button(action: onRequestBottomFocus) {
                        Label("返回底部菜单", systemImage: "chevron.down")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(SettingsBottomExitStyle())
                    .focused($bottomExitFocused)
                    .accessibilityIdentifier("settings-bottom-exit")
                    Spacer()
                    HStack { Text("uz影视 TV"); Spacer(); Text("基于原版协议 1.6.67 · tvOS 17+") }.foregroundStyle(UZTheme.secondaryText)
                }
                .padding(.horizontal, 54).padding(.top, 32)
                .defaultFocus($focusedDestination, .data)
            }
            .navigationDestination(item: $destination) { destination in
                switch destination {
                case .data: DataManagementView()
                case .playback: PlaybackSettingsView()
                default: PlaceholderSection(title: destination.title, icon: destination.icon, detail: "此项目正在适配 tvOS 遥控器")
                }
            }
        }
        .onAppear { requestSettingsFocus() }
        .onChange(of: focusRequest) { _, _ in requestSettingsFocus() }
        .onChange(of: bottomExitFocused) { _, focused in
            if focused { onRequestBottomFocus() }
        }
    }

    private func requestSettingsFocus() {
        focusedDestination = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            focusedDestination = .data
        }
    }
}

private struct SettingsBottomExitStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isFocused ? UZTheme.blue : UZTheme.secondaryText)
            .background(isFocused ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isFocused ? UZTheme.blue : .clear, lineWidth: 3))
    }
}

enum SettingsDestination: String, Identifiable {
    case data, features, playback, appearance, debug, tools
    var id: String { rawValue }
    var title: String {
        switch self {
        case .data: return "数据管理"
        case .features: return "功能设置"
        case .playback: return "播放设置"
        case .appearance: return "界面/语言"
        case .debug: return "扩展调试"
        case .tools: return "工具箱"
        }
    }
    var icon: String { self == .playback ? "play.rectangle" : "gearshape" }
}

struct SettingsRow: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Image(systemName: icon).frame(width: 35).foregroundStyle(UZTheme.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.title3).foregroundStyle(UZTheme.text)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(UZTheme.secondaryText) }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(UZTheme.secondaryText)
            }
            .padding(.horizontal, 24).frame(height: 68)
        }
        .buttonStyle(SettingsRowButtonStyle())
    }
}

private struct SettingsRowButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isFocused ? Color.white : UZTheme.surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(isFocused ? UZTheme.blue : UZTheme.border, lineWidth: isFocused ? 4 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.18 : 0), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.018 : 1))
    }
}

struct DataManagementView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            UZTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                SettingsPageHeader(title: "数据管理", onBack: { dismiss() })
                ScrollView {
                    LazyVStack(spacing: 12) {
                        DataManagementLink(title: "订阅", icon: "link", identifier: "data-subscription") { SubscriptionView() }
                        DataManagementLink(title: "视频源", icon: "play.rectangle", identifier: "data-sources") { SourcesView() }
                        DataManagementLink(title: "直播源", icon: "play.tv") { PlaceholderSection(title: "直播源", icon: "play.tv", detail: "等待导入原版直播扩展") }
                        DataManagementLink(title: "推荐扩展", icon: "sparkles") { PlaceholderSection(title: "推荐扩展", icon: "sparkles", detail: "等待导入原版推荐扩展") }
                        DataManagementLink(title: "网盘工具扩展", icon: "externaldrive.connected.to.line.below") { PlaceholderSection(title: "网盘工具扩展", icon: "externaldrive.connected.to.line.below", detail: "等待导入原版网盘扩展") }
                        DataManagementLink(title: "弹幕扩展", icon: "text.bubble") { PlaceholderSection(title: "弹幕扩展", icon: "text.bubble", detail: "等待导入原版弹幕扩展") }
                        DataManagementLink(title: "环境变量", icon: "terminal") { PlaceholderSection(title: "环境变量", icon: "terminal", detail: "暂无环境变量") }
                        DataManagementLink(title: "The Movie Database (TMDB)", icon: "film") { PlaceholderSection(title: "TMDB", icon: "film", detail: "尚未配置") }
                    }
                    .padding(.horizontal, 56)
                    .padding(.bottom, 30)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct DataManagementLink<Destination: View>: View {
    let title: String
    let icon: String
    var identifier: String = ""
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 20) {
                Image(systemName: icon).frame(width: 36).foregroundStyle(UZTheme.blue)
                Text(title).font(.title3.bold()).foregroundStyle(UZTheme.text)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(UZTheme.secondaryText)
            }
            .padding(.horizontal, 24)
            .frame(height: 68)
        }
        .buttonStyle(SettingsRowButtonStyle())
        .accessibilityIdentifier(identifier)
    }
}

struct SourcesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = "1111"

    var body: some View {
        ZStack {
            UZTheme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                SettingsPageHeader(title: "视频源", onBack: { dismiss() })
                HStack(spacing: 18) {
                    TextField("原版视频源分享码", text: $code)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .foregroundStyle(UZTheme.text)
                        .padding(.horizontal, 20)
                        .frame(height: 62)
                        .background(UZTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(UZTheme.border, lineWidth: 1))
                    Button("导入", systemImage: "plus") { Task { await store.importShareCode(code) } }
                        .buttonStyle(SearchActionButtonStyle())
                    Button("刷新", systemImage: "arrow.clockwise") { Task { await store.refresh() } }
                        .buttonStyle(SearchActionButtonStyle())
                }
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.sources) { source in
                            Button { Task { await store.select(source) } } label: {
                                HStack(spacing: 16) {
                                    Circle().fill(UZTheme.blue).frame(width: 14, height: 14)
                                    Text(source.name).font(.title3.bold()).foregroundStyle(UZTheme.text)
                                    Spacer()
                                    Image(systemName: "magnifyingglass")
                                    Image(systemName: "clock.arrow.circlepath")
                                    Image(systemName: source.isLock == true ? "lock" : "lock.open")
                                    if source == store.selectedSource { Image(systemName: "checkmark.circle.fill").foregroundStyle(UZTheme.blue) }
                                }
                                .foregroundStyle(UZTheme.secondaryText)
                                .padding(.horizontal, 22)
                                .frame(height: 68)
                            }
                            .buttonStyle(SourceListButtonStyle())
                        }
                    }
                }
            }.padding(.horizontal, 48).padding(.bottom, 36)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct SubscriptionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = "1111"
    var body: some View {
        ZStack {
            UZTheme.background.ignoresSafeArea()
            VStack(spacing: 28) {
                SettingsPageHeader(title: "订阅", onBack: { dismiss() })
                TextField("请输入原站订阅分享码", text: $code)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .foregroundStyle(UZTheme.text)
                    .padding(.horizontal, 22)
                    .frame(height: 66)
                    .background(UZTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(UZTheme.border, lineWidth: 1))
                Button("确定导入", systemImage: "square.and.arrow.down") { Task { await store.importSubscriptionCode(code) } }
                    .buttonStyle(SearchActionButtonStyle())
                Text(store.subscriptionStatus).foregroundStyle(UZTheme.secondaryText)
                Spacer()
            }.padding(.horizontal, 60).padding(.bottom, 50)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct PlaybackSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("play.hardwareDecode") private var hardwareDecode = true
    @AppStorage("play.showNext") private var showNext = true
    @AppStorage("play.pauseBackground") private var pauseInBackground = true
    @AppStorage("play.showDuration") private var showDuration = false

    var body: some View {
        ZStack {
            UZTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                SettingsPageHeader(title: "播放设置", onBack: { dismiss() })
                ScrollView {
                    LazyVStack(spacing: 12) {
                        PlaybackValueRow(title: "画面", value: "全面适应")
                        PlaybackToggleRow(title: "硬解码", isOn: $hardwareDecode)
                        PlaybackToggleRow(title: "显示上一集下一集按钮", isOn: $showNext)
                        PlaybackToggleRow(title: "进入后台暂停播放", isOn: $pauseInBackground)
                        PlaybackToggleRow(title: "显示总时长", isOn: $showDuration)
                        PlaybackValueRow(title: "全局倍速设定", value: "1.0")
                        PlaybackValueRow(title: "快进快退", value: "10 秒")
                        PlaybackValueRow(title: "遥控器", value: "使用 tvOS 原生播放控制")
                    }
                    .padding(.horizontal, 56)
                    .padding(.bottom, 30)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct SettingsPageHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Label("返回", systemImage: "chevron.left")
                    .font(.headline.bold())
                    .frame(width: 168, height: 52)
            }
            .buttonStyle(SettingsHeaderButtonStyle())
            Spacer()
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(UZTheme.text)
            Spacer()
            Color.clear.frame(width: 168, height: 52)
        }
        .padding(.horizontal, 52)
        .padding(.top, 18)
        .padding(.bottom, 18)
    }
}

private struct SettingsHeaderButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isFocused ? Color.white : UZTheme.text)
            .background(isFocused ? UZTheme.blue : UZTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isFocused ? Color.white : UZTheme.border, lineWidth: isFocused ? 3 : 1))
            .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.06 : 1))
    }
}

private struct PlaybackToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack {
                Text(title).font(.title3.bold()).foregroundStyle(UZTheme.text)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? UZTheme.blue : UZTheme.secondaryText)
                Text(isOn ? "开启" : "关闭").font(.headline).foregroundStyle(UZTheme.secondaryText)
            }
            .padding(.horizontal, 24).frame(height: 68)
        }
        .buttonStyle(SettingsRowButtonStyle())
    }
}

private struct PlaybackValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).font(.title3.bold()).foregroundStyle(UZTheme.text)
            Spacer()
            Text(value).font(.headline).foregroundStyle(UZTheme.secondaryText)
        }
        .padding(.horizontal, 24).frame(height: 68)
        .background(UZTheme.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(UZTheme.border, lineWidth: 1))
    }
}
