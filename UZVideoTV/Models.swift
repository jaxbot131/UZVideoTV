import Foundation

struct VideoSource: Codable, Identifiable, Hashable, Sendable {
    var id: String { api }
    let api: String
    let name: String
    var noHistory: Bool?
    var isLock: Bool?
}

struct VideoCategory: Codable, Identifiable, Hashable {
    let id: Int
    let parentID: Int
    let name: String

    init?(json: [String: Any]) {
        guard let id = Self.int(json["type_id"]), id > 0 else { return nil }
        self.id = id
        parentID = Self.int(json["type_pid"]) ?? 0
        name = json["type_name"] as? String ?? "分类"
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}

struct VideoItem: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let poster: String
    let remarks: String
    let summary: String
    let playURL: String
    let playFrom: String
    let typeID: Int
    let typeName: String
    let actor: String
    let director: String
    let year: String
    let area: String
    let genre: String?
    let score: Double?
    let hits: Int?

    var posterURL: URL? { URL(string: poster) }

    init(json: [String: Any]) {
        if let number = json["vod_id"] as? NSNumber {
            id = number.stringValue
        } else {
            id = String(describing: json["vod_id"] ?? UUID().uuidString)
        }
        name = json["vod_name"] as? String ?? "未命名"
        poster = json["vod_pic"] as? String ?? ""
        remarks = json["vod_remarks"] as? String ?? ""
        summary = (json["vod_content"] as? String) ?? (json["vod_blurb"] as? String) ?? ""
        playURL = json["vod_play_url"] as? String ?? ""
        playFrom = json["vod_play_from"] as? String ?? ""
        typeID = (json["type_id"] as? NSNumber)?.intValue ?? Int(json["type_id"] as? String ?? "") ?? 0
        typeName = json["type_name"] as? String ?? ""
        actor = json["vod_actor"] as? String ?? ""
        director = json["vod_director"] as? String ?? ""
        year = String(describing: json["vod_year"] ?? "")
        area = json["vod_area"] as? String ?? ""
        genre = json["vod_class"] as? String
        if let number = json["vod_score"] as? NSNumber {
            score = number.doubleValue
        } else {
            score = Double(String(describing: json["vod_score"] ?? ""))
        }
        if let number = json["vod_hits"] as? NSNumber {
            hits = number.intValue
        } else {
            hits = Int(String(describing: json["vod_hits"] ?? ""))
        }
    }

    var cleanSummary: String {
        summary
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var lines: [PlayLine] {
        let names = playFrom.components(separatedBy: "$$$")
        return playURL.components(separatedBy: "$$$").enumerated().compactMap { index, group in
            let episodes = group.components(separatedBy: "#").compactMap { entry -> Episode? in
                let parts = entry.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 2,
                      let url = URL(string: parts[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
                return Episode(title: parts[0].isEmpty ? "播放" : parts[0], url: url, lineIndex: index)
            }
            guard !episodes.isEmpty else { return nil }
            let rawName = names.indices.contains(index) ? names[index] : "线路\(index + 1)"
            return PlayLine(id: index, name: rawName.isEmpty ? "线路\(index + 1)" : rawName, episodes: episodes)
        }
    }

    var preferredLine: PlayLine? {
        lines.first(where: { line in line.episodes.contains(where: { $0.isDirectStream }) }) ?? lines.first
    }
}

struct RecommendationItem: Identifiable, Hashable, Sendable {
    let source: VideoSource
    let video: VideoItem

    var id: String { "\(source.api)|\(video.id)" }
}

enum RecommendationCatalogKind: String, CaseIterable, Identifiable, Sendable {
    case all
    case tv
    case movie
    case variety

    var id: String { rawValue }
}

struct DoubanRecommendation: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let year: String
    let poster: String
    let subtitle: String
    let score: Double?
    let ratingCount: Int

    var posterURL: URL? { URL(string: poster) }

    init(json: [String: Any]) {
        id = String(describing: json["id"] ?? UUID().uuidString)
        title = json["title"] as? String ?? "未命名"
        year = String(describing: json["year"] ?? "")
        subtitle = json["card_subtitle"] as? String ?? ""
        let pic = json["pic"] as? [String: Any]
        poster = (pic?["large"] as? String) ?? (pic?["normal"] as? String) ?? ""
        let rating = json["rating"] as? [String: Any]
        if let value = rating?["value"] as? NSNumber {
            score = value.doubleValue
        } else {
            score = Double(String(describing: rating?["value"] ?? ""))
        }
        if let value = rating?["count"] as? NSNumber {
            ratingCount = value.intValue
        } else {
            ratingCount = Int(String(describing: rating?["count"] ?? "")) ?? 0
        }
    }
}

struct PlayLine: Identifiable, Hashable {
    let id: Int
    let name: String
    let episodes: [Episode]
}

struct Episode: Identifiable, Hashable {
    var id: String { "\(lineIndex)-\(url.absoluteString)" }
    let title: String
    let url: URL
    let lineIndex: Int

    var isDirectStream: Bool {
        let path = url.path.lowercased()
        return path.contains(".m3u8") || path.contains(".mp4") || path.contains(".mov")
    }
}

struct PlaybackRecord: Codable, Identifiable, Hashable {
    var id: String { video.id }
    let video: VideoItem
    let episodeTitle: String
    let episodeURL: String?
    let lineIndex: Int?
    let progressSeconds: Double?
    let durationSeconds: Double?
    let playedAt: Date

    var progress: Double {
        guard let progressSeconds, let durationSeconds, durationSeconds > 0 else { return 0 }
        return min(max(progressSeconds / durationSeconds, 0), 1)
    }
}

enum UZError: LocalizedError {
    case invalidURL
    case invalidResponse
    case noSource
    case noEpisodes
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "地址无效"
        case .invalidResponse: return "服务器返回了无法识别的数据；该视频源可能不是 JSON 采集接口"
        case .noSource: return "请先在“视频源”中导入分享码并选择一个视频源"
        case .noEpisodes: return "这个条目没有可播放的剧集地址"
        case .server(let message): return message
        }
    }
}
