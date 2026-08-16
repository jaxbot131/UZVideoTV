import AVKit
import Combine
import SwiftUI

private struct EpisodeSkipSettings: Codable, Equatable {
    var introEndSeconds: Double?
    var outroRemainingSeconds: Double?

    var isEmpty: Bool { introEndSeconds == nil && outroRemainingSeconds == nil }
}

private enum EpisodeSkipStore {
    private static let defaultsKey = "player.episodeSkipSettings"

    static func key(for video: VideoItem) -> String {
        "\(video.id)|\(video.name)|\(video.year)"
    }

    static func load(for video: VideoItem) -> EpisodeSkipSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let all = try? JSONDecoder().decode([String: EpisodeSkipSettings].self, from: data) else {
            return EpisodeSkipSettings()
        }
        return all[key(for: video)] ?? EpisodeSkipSettings()
    }

    static func save(_ settings: EpisodeSkipSettings, for video: VideoItem) {
        var all: [String: EpisodeSkipSettings] = [:]
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: EpisodeSkipSettings].self, from: data) {
            all = decoded
        }
        if settings.isEmpty {
            all.removeValue(forKey: key(for: video))
        } else {
            all[key(for: video)] = settings
        }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

struct PlayerScreen: View {
    @EnvironmentObject private var store: AppStore
    let video: VideoItem
    let episode: Episode
    let initialPosition: Double
    let previousEpisode: Episode?
    let nextEpisode: Episode?
    var onChangeEpisode: ((Episode) -> Void)?
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer
    @State private var statusText = "正在连接视频…"
    @State private var playbackError: String?
    @State private var isPlaying = false
    @State private var timeObserver: Any?
    @State private var controlMessage: String?
    @State private var fillVideo = false
    @State private var skipSettings: EpisodeSkipSettings
    @State private var didApplyIntro = false
    @State private var didTriggerOutro = false
    @State private var didApplyInitialPosition = false
    @State private var lastSavedSecond = -10.0
    @State private var isChangingEpisode = false

    init(
        video: VideoItem,
        episode: Episode,
        initialPosition: Double = 0,
        previousEpisode: Episode? = nil,
        nextEpisode: Episode? = nil,
        onChangeEpisode: ((Episode) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.video = video
        self.episode = episode
        self.initialPosition = max(0, initialPosition)
        self.previousEpisode = previousEpisode
        self.nextEpisode = nextEpisode
        self.onChangeEpisode = onChangeEpisode
        self.onClose = onClose
        // Let AVFoundation issue its native HLS requests. Injected Referer
        // headers can be propagated to a playlist's secondary CDN and are
        // rejected by CoreMedia on physical Apple TV hardware.
        _player = State(initialValue: AVPlayer(url: episode.url))
        _skipSettings = State(initialValue: EpisodeSkipStore.load(for: video))
        _didApplyIntro = State(initialValue: initialPosition > 0)
    }

    var body: some View {
        ZStack {
            PlayerController(
                player: player,
                fillVideo: fillVideo,
                title: video.name,
                subtitle: episode.title,
                onPreviousEpisode: previousEpisode.map { item in
                    { changeEpisode(to: item) }
                },
                onNextEpisode: nextEpisode.map { item in
                    { changeEpisode(to: item) }
                },
                onEpisodeList: { close() },
                onSubtitles: { cycleSubtitles() },
                onAudioTrack: { cycleAudioTrack() },
                onVideoFit: {
                    fillVideo.toggle()
                    showControlMessage(fillVideo ? "画面：填满屏幕" : "画面：完整显示")
                },
                skipSettings: skipSettings,
                onSetIntro: { setIntroPoint() },
                onSetOutro: { setOutroPoint() },
                onClearSkip: { clearSkipSettings() }
            )
            .ignoresSafeArea()

            if player.currentItem?.status == .unknown && playbackError == nil {
                VStack(spacing: 18) {
                    ProgressView().scaleEffect(1.4)
                    Text(statusText).font(.title3)
                    Text(episode.url.host ?? "").font(.caption).foregroundStyle(.secondary)
                }
                .padding(36).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
            }

            if let playbackError {
                VStack(spacing: 22) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 52)).foregroundStyle(.yellow)
                    Text("无法播放").font(.largeTitle.bold())
                    Text(playbackError).multilineTextAlignment(.center).frame(maxWidth: 900)
                    Text("这个地址可能已失效、被视频站限制访问，或不是 Apple TV 支持的直链。请返回切换其他线路或视频源。")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 900)
                    HStack {
                        Button("重试", systemImage: "arrow.clockwise") { retry() }
                        Button("返回选集", systemImage: "chevron.backward") { close() }
                    }
                }
                .padding(48).background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 26))
            }

            if let controlMessage {
                VStack {
                    Spacer()
                    Text(controlMessage)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color.black.opacity(0.8), in: Capsule())
                        .padding(.bottom, 190)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playerScreen")
        .accessibilityValue(playbackError ?? (statusText.isEmpty ? "ready" : "loading"))
        .onAppear {
            statusText = episode.isDirectStream ? "正在连接视频…" : "正在尝试解析此线路…"
            installTimeObserver()
            player.play()
        }
        .onDisappear {
            if !isChangingEpisode { saveProgress(force: true) }
            player.pause()
            if let timeObserver {
                player.removeTimeObserver(timeObserver)
                self.timeObserver = nil
            }
        }
        .onReceive(player.currentItem!.publisher(for: \.status)) { status in
            switch status {
            case .readyToPlay:
                playbackError = nil
                statusText = ""
                applyInitialPositionIfNeeded()
            case .failed:
                playbackError = player.currentItem?.error?.localizedDescription ?? "播放器无法读取该视频地址"
            default: break
            }
        }
        .onReceive(player.publisher(for: \.timeControlStatus)) { status in
            isPlaying = status == .playing
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)) { notification in
            let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            playbackError = error?.localizedDescription ?? "播放连接已中断"
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let endedItem = notification.object as? AVPlayerItem,
                  endedItem === player.currentItem,
                  !isChangingEpisode else { return }
            saveProgress(force: true)
            if let nextEpisode {
                showControlMessage("本集播放完毕，正在播放下一集")
                changeEpisode(to: nextEpisode, delay: 0.45)
            } else {
                showControlMessage("已播放完最后一集")
            }
        }
        .onExitCommand { close() }
    }

    private func retry() {
        playbackError = nil
        statusText = "正在重新连接…"
        player.seek(to: .zero)
        player.play()
    }

    private func close() {
        saveProgress(force: true)
        player.pause()
        if let onClose { onClose() } else { dismiss() }
    }

    private func togglePlayback() {
        player.timeControlStatus == .playing ? player.pause() : player.play()
    }

    private func applyInitialPositionIfNeeded() {
        guard !didApplyInitialPosition else {
            player.play()
            return
        }
        didApplyInitialPosition = true
        let duration = player.currentItem?.duration.seconds ?? 0
        let safePosition: Double
        if duration.isFinite, duration > 0 {
            safePosition = min(initialPosition, max(0, duration - 3))
        } else {
            safePosition = initialPosition
        }
        guard safePosition >= 1 else {
            player.play()
            return
        }
        player.seek(
            to: CMTime(seconds: safePosition, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600)
        ) { _ in
            player.play()
            showControlMessage("已从 \(timeText(safePosition)) 继续播放")
        }
    }

    private func saveProgress(force: Bool = false, time: Double? = nil) {
        // Do not replace a saved resume point with 0 while a newly-created
        // AVPlayerItem is still preparing and has not performed its first seek.
        if initialPosition >= 1, !didApplyInitialPosition { return }
        let current = time ?? player.currentTime().seconds
        guard current.isFinite, current >= 0 else { return }
        if !force, abs(current - lastSavedSecond) < 5 { return }
        lastSavedSecond = current
        let durationValue = player.currentItem?.duration.seconds
        let duration = durationValue?.isFinite == true ? durationValue : nil
        store.recordPlayback(
            video: video,
            episode: episode,
            progressSeconds: current,
            durationSeconds: duration
        )
    }

    private func changeEpisode(to newEpisode: Episode, delay: Double = 0.15) {
        guard !isChangingEpisode else { return }
        isChangingEpisode = true
        player.pause()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            onChangeEpisode?(newEpisode)
        }
    }

    private func cycleSubtitles() {
        guard let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible),
              !group.options.isEmpty else {
            showControlMessage("没有可用字幕")
            return
        }
        let current = item.currentMediaSelection.selectedMediaOption(in: group)
        if let current, let index = group.options.firstIndex(of: current), index + 1 < group.options.count {
            let next = group.options[index + 1]
            item.select(next, in: group)
            showControlMessage("字幕：\(next.displayName)")
        } else if current != nil {
            item.select(nil, in: group)
            showControlMessage("字幕：关闭")
        } else if let first = group.options.first {
            item.select(first, in: group)
            showControlMessage("字幕：\(first.displayName)")
        }
    }

    private func cycleAudioTrack() {
        guard let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
              !group.options.isEmpty else {
            showControlMessage("没有其他音轨")
            return
        }
        let current = item.currentMediaSelection.selectedMediaOption(in: group)
        let currentIndex = current.flatMap { group.options.firstIndex(of: $0) } ?? -1
        let next = group.options[(currentIndex + 1) % group.options.count]
        item.select(next, in: group)
        showControlMessage("音轨：\(next.displayName)")
    }

    private func showControlMessage(_ message: String) {
        controlMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if controlMessage == message { controlMessage = nil }
        }
    }

    private func setIntroPoint() {
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds >= 1 else {
            showControlMessage("请先把进度移到正片开始位置")
            return
        }
        skipSettings.introEndSeconds = seconds
        EpisodeSkipStore.save(skipSettings, for: video)
        didApplyIntro = true
        showControlMessage("已为《\(video.name)》设置片头：\(timeText(seconds))")
    }

    private func setOutroPoint() {
        let current = player.currentTime().seconds
        let duration = player.currentItem?.duration.seconds ?? 0
        guard current.isFinite, duration.isFinite, duration > current else {
            showControlMessage("请在片尾字幕刚开始时设置")
            return
        }
        let remaining = duration - current
        guard remaining >= 5 else {
            showControlMessage("位置太接近结尾，请移到片尾刚开始的位置")
            return
        }
        skipSettings.outroRemainingSeconds = remaining
        EpisodeSkipStore.save(skipSettings, for: video)
        showControlMessage("已为《\(video.name)》设置片尾：剩余 \(timeText(remaining))")
    }

    private func clearSkipSettings() {
        skipSettings = EpisodeSkipSettings()
        EpisodeSkipStore.save(skipSettings, for: video)
        didApplyIntro = true
        didTriggerOutro = false
        showControlMessage("已清除《\(video.name)》的片头片尾设置")
    }

    private func installTimeObserver() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { time in
            let current = time.seconds
            guard current.isFinite else { return }

            saveProgress(time: current)

            if !didApplyIntro,
               let introEnd = skipSettings.introEndSeconds,
               introEnd >= 1,
               current < introEnd - 0.5 {
                didApplyIntro = true
                player.seek(to: CMTime(seconds: introEnd, preferredTimescale: 600))
                showControlMessage("已跳过《\(video.name)》片头")
                return
            }
            if !didApplyIntro, current >= 1 {
                didApplyIntro = true
            }

            guard !didTriggerOutro,
                  let remaining = skipSettings.outroRemainingSeconds else { return }
            let duration = player.currentItem?.duration.seconds ?? 0
            guard duration.isFinite, duration > remaining else { return }
            let outroStart = duration - remaining
            guard current >= outroStart else { return }

            didTriggerOutro = true
            if let nextEpisode {
                showControlMessage("已跳过片尾，正在播放下一集")
                changeEpisode(to: nextEpisode)
            } else {
                showControlMessage("已跳过片尾")
                player.seek(to: CMTime(seconds: duration, preferredTimescale: 600))
                player.pause()
            }
        }
    }

    private func timeText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct PlayerController: UIViewControllerRepresentable {
    let player: AVPlayer
    let fillVideo: Bool
    let title: String
    let subtitle: String
    let onPreviousEpisode: (() -> Void)?
    let onNextEpisode: (() -> Void)?
    let onEpisodeList: () -> Void
    let onSubtitles: () -> Void
    let onAudioTrack: () -> Void
    let onVideoFit: () -> Void
    let skipSettings: EpisodeSkipSettings
    let onSetIntro: () -> Void
    let onSetOutro: () -> Void
    let onClearSkip: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.playbackControlsIncludeTransportBar = true
        controller.playbackControlsIncludeInfoViews = true
        controller.transportBarIncludesTitleView = true
        controller.isSkipBackwardEnabled = true
        controller.isSkipForwardEnabled = true
        controller.skippingBehavior = .default
        controller.videoGravity = fillVideo ? .resizeAspectFill : .resizeAspect
        configureMetadata()
        controller.transportBarCustomMenuItems = context.coordinator.menuItems()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.parent = self
        controller.player = player
        controller.videoGravity = fillVideo ? .resizeAspectFill : .resizeAspect
        configureMetadata()
        controller.transportBarCustomMenuItems = context.coordinator.menuItems()
    }

    private func configureMetadata() {
        guard let item = player.currentItem else { return }
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = title as NSString
        let subtitleItem = AVMutableMetadataItem()
        subtitleItem.identifier = .iTunesMetadataTrackSubTitle
        subtitleItem.value = subtitle as NSString
        item.externalMetadata = [titleItem, subtitleItem]
    }

    final class Coordinator {
        var parent: PlayerController

        init(parent: PlayerController) {
            self.parent = parent
        }

        func menuItems() -> [UIMenuElement] {
            [
                action(
                    title: skipTitle(prefix: "设片头", seconds: parent.skipSettings.introEndSeconds),
                    systemName: "forward.frame.fill",
                    handler: parent.onSetIntro
                ),
                action(
                    title: skipTitle(prefix: "设片尾", seconds: parent.skipSettings.outroRemainingSeconds),
                    systemName: "backward.frame.fill",
                    handler: parent.onSetOutro
                ),
                action(
                    title: "清除跳过",
                    systemName: "xmark.circle",
                    enabled: !parent.skipSettings.isEmpty,
                    handler: parent.onClearSkip
                ),
                action(
                    title: "上一集",
                    systemName: "backward.end.fill",
                    enabled: parent.onPreviousEpisode != nil,
                    handler: { self.parent.onPreviousEpisode?() }
                ),
                action(
                    title: "下一集",
                    systemName: "forward.end.fill",
                    enabled: parent.onNextEpisode != nil,
                    handler: { self.parent.onNextEpisode?() }
                ),
                action(title: "选集", systemName: "rectangle.stack", handler: parent.onEpisodeList),
                action(title: "字幕", systemName: "captions.bubble", handler: parent.onSubtitles),
                action(title: "音轨", systemName: "waveform", handler: parent.onAudioTrack),
                action(
                    title: parent.fillVideo ? "完整显示" : "填满屏幕",
                    systemName: parent.fillVideo ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    handler: parent.onVideoFit
                )
            ]
        }

        private func skipTitle(prefix: String, seconds: Double?) -> String {
            guard let seconds else { return prefix }
            let total = max(0, Int(seconds.rounded()))
            return "\(prefix) \(total / 60):\(String(format: "%02d", total % 60))"
        }

        private func action(
            title: String,
            systemName: String,
            enabled: Bool = true,
            handler: @escaping () -> Void
        ) -> UIAction {
            UIAction(
                title: title,
                image: UIImage(systemName: systemName),
                attributes: enabled ? [] : [.disabled]
            ) { _ in handler() }
        }
    }
}
