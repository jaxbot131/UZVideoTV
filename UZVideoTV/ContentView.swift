import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case home = "首页"
    case recommend = "推荐"
    case live = "电视"
    case collection = "收藏"
    case settings = "设置"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "play.circle.fill"
        case .recommend: return "sparkles"
        case .live: return "play.tv"
        case .collection: return "arrow.down.to.line"
        case .settings: return "gearshape.fill"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var section: MainSection
    @State private var contentFocusRequest = 0
    @State private var lastFocusWasBottom = false
    @FocusState private var bottomFocus: MainSection?
    @FocusState private var bottomBridgeFocused: Bool

    init() {
        let initialSection: MainSection = ProcessInfo.processInfo.arguments.contains("-UITestRecommend") ? .recommend : .home
        _section = State(initialValue: initialSection)
    }

    var body: some View {
        ZStack {
            UZTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Group {
                    switch section {
                    case .home: HomeView(focusRequest: contentFocusRequest) {
                        lastFocusWasBottom = true
                        bottomFocus = .home
                    }
                    case .recommend: RecommendView()
                    case .live: PlaceholderSection(title: "电视直播", icon: "play.tv", detail: "直播源将在数据管理中显示")
                    case .collection: CollectionView()
                    case .settings: SettingsView(focusRequest: contentFocusRequest) {
                        lastFocusWasBottom = true
                        bottomFocus = .settings
                    }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 12)
                    .focusable(true)
                    .focused($bottomBridgeFocused)
                    .accessibilityHidden(true)
                BottomNavigation(selection: $section, focusedItem: $bottomFocus)
                    .frame(height: 82)
            }
            .onChange(of: bottomBridgeFocused) { _, isFocused in
                guard isFocused else { return }
                if lastFocusWasBottom {
                    // Moving up from the bar: skip the invisible bridge and
                    // restore a deterministic focus target in the content.
                    lastFocusWasBottom = false
                    bottomFocus = nil
                    contentFocusRequest += 1
                } else {
                    // Moving down from content: enter the bar at the currently
                    // selected tab instead of making the user hunt for it.
                    bottomFocus = section
                    lastFocusWasBottom = true
                }
            }
            .onChange(of: bottomFocus) { _, item in
                if item != nil { lastFocusWasBottom = true }
            }
        }
        .preferredColorScheme(.light)
        .overlay {
            if store.isLoading {
                ZStack {
                    Color.black.opacity(0.24).ignoresSafeArea()
                    VStack(spacing: 22) {
                        ProgressView().scaleEffect(1.35)
                        Text(store.loadingMessage).font(.title3)
                    }
                    .padding(.horizontal, 52).padding(.vertical, 34)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                }
            }
        }
        .alert("提示", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct BottomNavigation: View {
    @Binding var selection: MainSection
    var focusedItem: FocusState<MainSection?>.Binding

    var body: some View {
        HStack(spacing: 88) {
            ForEach(MainSection.allCases) { item in
                Button { selection = item } label: {
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(focusedItem.wrappedValue == item ? UZTheme.blue : .clear)
                            .frame(width: 34, height: 4)
                        Image(systemName: item.icon).font(.system(size: 31, weight: .semibold))
                        Text(item.rawValue).font(.callout.bold())
                    }
                    .frame(width: 126, height: 72)
                    .foregroundStyle(selection == item ? UZTheme.blue : UZTheme.text)
                }
                .buttonStyle(NavButtonStyle(selected: selection == item))
                .accessibilityIdentifier("bottom-\(item.rawValue)")
                .focused(focusedItem, equals: item)
            }
        }
        .focusSection()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.97))
    }
}

private struct NavButtonStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isFocused || selected ? UZTheme.blue : UZTheme.text)
            .background(isFocused ? Color.white : (selected ? UZTheme.blue.opacity(0.10) : .clear), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(isFocused ? UZTheme.blue : .clear, lineWidth: 4))
            .shadow(color: .black.opacity(isFocused ? 0.22 : 0), radius: 16, y: 7)
            .scaleEffect(configuration.isPressed ? 0.94 : (isFocused ? 1.10 : 1))
            .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    let focusRequest: Int
    let onRequestBottomFocus: () -> Void
    @State private var selectedVideo: VideoItem?
    @State private var showSearch = false
    @State private var showCollection = false
    @State private var showHistory = false
    @State private var showSourcePicker = false
    @FocusState private var focusedHeader: HeaderFocus?
    @FocusState private var focusedFooter: HomeFooterFocus?

    private let columns = Array(repeating: GridItem(.fixed(250), spacing: 26), count: 6)

    init(focusRequest: Int = 0, onRequestBottomFocus: @escaping () -> Void = {}) {
        self.focusRequest = focusRequest
        self.onRequestBottomFocus = onRequestBottomFocus
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            categories
            if store.sources.isEmpty {
                ContentUnavailableView("还没有视频源", systemImage: "tv.slash", description: Text("前往设置 → 数据管理 → 视频源，导入原版分享码（例如 1111）"))
                    .foregroundStyle(UZTheme.text)
            } else if store.videos.isEmpty && !store.isLoading {
                ContentUnavailableView("没有找到影片", systemImage: "film.stack", description: Text("可以切换分类、视频源或刷新重试"))
                    .foregroundStyle(UZTheme.text)
            } else {
                ScrollView {
                    VStack(spacing: 28) {
                        LazyVGrid(columns: columns, spacing: 34) {
                            ForEach(store.videos) { video in
                                Button { open(video) } label: { PosterCard(video: video) }
                                    .buttonStyle(PosterFocusStyle())
                                    .accessibilityIdentifier("poster-\(video.id)")
                            }
                        }
                        homeFooter
                    }
                    .padding(.horizontal, 42)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
        }
        .fullScreenCover(item: $selectedVideo) { DetailView(video: $0) }
        .sheet(isPresented: $showSearch) { NavigationStack { SearchView() } }
        .sheet(isPresented: $showCollection) {
            NavigationStack { CollectionView(showCloseButton: true, initiallyShowingHistory: showHistory) }
        }
        .fullScreenCover(isPresented: $showSourcePicker) { SourcePickerView() }
        .defaultFocus($focusedHeader, .source)
        .onAppear { requestHeaderFocus() }
        .onChange(of: store.isLoading) { _, isLoading in
            if !isLoading { requestHeaderFocus() }
        }
        .onChange(of: focusRequest) { _, _ in requestHeaderFocus() }
    }

    private var homeFooter: some View {
        VStack(spacing: 14) {
            if store.hasMoreVideos {
                Button {
                    Task { await store.loadMoreVideos() }
                } label: {
                    Label(store.isLoadingMoreVideos ? "正在加载…" : "继续加载下一页", systemImage: "arrow.down.circle.fill")
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity, minHeight: 58)
                }
                .buttonStyle(CategoryButtonStyle(selected: false))
                .focused($focusedFooter, equals: .loadMore)
                .disabled(store.isLoadingMoreVideos)
                .accessibilityIdentifier("home-load-more")
                .onMoveCommand { direction in
                    if direction == .down { focusedFooter = .bottomMenu }
                }
            } else {
                Text(store.currentCatalogPage > 1 ? "已经加载全部资源" : "当前源没有更多资源")
                    .font(.callout.bold()).foregroundStyle(UZTheme.secondaryText)
            }
            Button(action: onRequestBottomFocus) {
                Label("进入底部菜单", systemImage: "chevron.down")
                    .font(.callout.bold())
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(CategoryButtonStyle(selected: false))
            .focused($focusedFooter, equals: .bottomMenu)
            .accessibilityIdentifier("home-bottom-exit")
            .onMoveCommand { direction in
                if direction == .up, store.hasMoreVideos { focusedFooter = .loadMore }
                if direction == .down { onRequestBottomFocus() }
            }
        }
        .focusSection()
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: 18) {
            Image(systemName: "storefront").font(.system(size: 31, weight: .bold))
            Button { showSourcePicker = true } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(UZTheme.blue)
                        .frame(width: 17, height: 17)
                    Text(store.selectedSource?.name ?? "uz影视").font(.title2.bold())
                    Image(systemName: "chevron.down").font(.caption.bold())
                }
            }
            .buttonStyle(SourceButtonStyle())
            .accessibilityIdentifier("sourcePickerButton")
            .accessibilityLabel(store.selectedSource?.name ?? "选择视频源")
            .focused($focusedHeader, equals: .source)
            .onMoveCommand { if $0 == .right { focusedHeader = .history } }
            Spacer()
            Button {
                showHistory = true
                showCollection = true
            } label: { Image(systemName: "clock.arrow.circlepath") }
                .buttonStyle(HeaderButtonStyle())
                .focused($focusedHeader, equals: .history)
                .accessibilityIdentifier("header-history")
                .accessibilityLabel("播放历史")
                .onMoveCommand {
                    if $0 == .left { focusedHeader = .source }
                    if $0 == .right { focusedHeader = .favorites }
                }
            Button {
                showHistory = false
                showCollection = true
            } label: { Image(systemName: "heart") }
                .buttonStyle(HeaderButtonStyle())
                .focused($focusedHeader, equals: .favorites)
                .accessibilityIdentifier("header-favorites")
                .accessibilityLabel("收藏")
                .onMoveCommand {
                    if $0 == .left { focusedHeader = .history }
                    if $0 == .right { focusedHeader = .search }
                }
            Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(HeaderButtonStyle())
                .focused($focusedHeader, equals: .search)
                .accessibilityIdentifier("header-search")
                .accessibilityLabel("搜索")
                .onMoveCommand { if $0 == .left { focusedHeader = .favorites } }
        }
        .focusSection()
        .font(.system(size: 29, weight: .medium))
        .padding(.horizontal, 44)
        .frame(height: 82)
    }

    private var categories: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                CategoryButton(title: "最新", selected: store.selectedCategoryID == nil) {
                    Task { await store.selectCategory(nil) }
                }
                .accessibilityIdentifier("category-latest")
                ForEach(store.categories) { category in
                    CategoryButton(title: displayCategory(category.name), selected: store.selectedCategoryID == category.id) {
                        Task { await store.selectCategory(category.id) }
                    }
                    .accessibilityIdentifier("category-\(category.id)")
                }
            }
            .padding(.horizontal, 42).padding(.vertical, 9)
        }
        .frame(height: 68)
    }

    private func displayCategory(_ name: String) -> String {
        name.replacingOccurrences(of: "片", with: "")
    }

    private func open(_ video: VideoItem) {
        Task {
            if let detail = await store.fullDetail(for: video) { selectedVideo = detail }
        }
    }

    private func requestHeaderFocus() {
        // A physical Apple TV can finish establishing its focus system after
        // the initial network-loading overlay disappears. Re-asserting the
        // default here makes the first remote action deterministic.
        focusedHeader = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusedHeader = .source
        }
    }
}

private enum HeaderFocus: Hashable {
    case source
    case history
    case favorites
    case search
}

private enum HomeFooterFocus: Hashable {
    case loadMore
    case bottomMenu
}

private struct SourceButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isFocused ? UZTheme.blue : UZTheme.text)
            .padding(.horizontal, 7)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(isFocused ? UZTheme.blue : Color.clear)
                    .frame(height: 4)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? 1.06 : 1))
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

struct CategoryButton: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if selected { Image(systemName: "checkmark").font(.caption.bold()) }
                Text(title).font(.headline)
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
        }
        .buttonStyle(CategoryButtonStyle(selected: selected))
    }
}

private struct CategoryButtonStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isFocused ? UZTheme.blue : (selected ? Color.white : UZTheme.text))
            .background(isFocused ? Color.white : (selected ? UZTheme.blue : UZTheme.surface), in: Capsule())
            .overlay(Capsule().stroke(isFocused ? UZTheme.blue : UZTheme.border, lineWidth: isFocused ? 4 : 1))
            .shadow(color: .black.opacity(isFocused ? 0.22 : 0.06), radius: 12, y: 5)
            .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.10 : 1))
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

struct PosterCard: View {
    let video: VideoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: video.posterURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default:
                        ZStack {
                            LinearGradient(colors: [Color.gray.opacity(0.18), Color.gray.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                            Image(systemName: "film").font(.system(size: 45)).foregroundStyle(UZTheme.secondaryText)
                        }
                    }
                }
                .frame(width: 250, height: 360)
                .clipped()
                if !video.remarks.isEmpty {
                    Text(video.remarks).font(.caption2).lineLimit(1)
                        .foregroundStyle(UZTheme.text)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 5))
                        .padding(7)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(video.name).font(.headline).foregroundStyle(UZTheme.text).lineLimit(1)
        }
        .frame(width: 250, alignment: .leading)
    }
}

struct PosterFocusStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(7)
            .background(isFocused ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isFocused ? UZTheme.blue : .clear, lineWidth: 4))
            .shadow(color: .black.opacity(isFocused ? 0.22 : 0), radius: 18, y: 8)
            .scaleEffect(isFocused ? 1.06 : (configuration.isPressed ? 0.97 : 1))
            .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}

struct HeaderButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(UZTheme.text)
            .frame(width: 58, height: 48)
            .background(isFocused ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(isFocused ? UZTheme.blue : .clear, lineWidth: 4))
            .scaleEffect(configuration.isPressed ? 0.9 : (isFocused ? 1.10 : 1))
    }
}

enum UZTheme {
    static let background = Color(red: 0.955, green: 0.965, blue: 0.985)
    static let blue = Color(red: 0.0, green: 0.34, blue: 0.58)
    static let text = Color(red: 0.10, green: 0.12, blue: 0.16)
    static let secondaryText = Color(red: 0.25, green: 0.28, blue: 0.34)
    static let surface = Color.white.opacity(0.94)
    static let border = Color.black.opacity(0.18)
}
