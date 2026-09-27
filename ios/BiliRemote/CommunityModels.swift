import Foundation

struct CreatorProfile: Decodable {
    let id: String, name: String, url: String
    let avatar: String?, description: String?
    let followers: Int, following: Int, videoCount: Int, likes: Int, level: Int
    let verified: String
}
struct FavoriteFolder: Codable, Identifiable {
    let id: String, title: String
    let count: Int
}
struct FavoriteFolders: Decodable { let accountName: String; let items: [FavoriteFolder] }
struct FeedVideo: Codable, Identifiable, Hashable {
    let bvid: String
    let title: String
    let url: String
    var cover: String?
    var duration: Double?
    var creatorId: String?
    var creatorName: String?
    var views: Int?
    var danmaku: Int?
    var publishedAt: Double?
    var reason: String?
    var id: String { bvid }
    var video: VideoItem { VideoItem(bvid: bvid, title: title, url: url, cover: cover, duration: duration, creatorId: creatorId, creatorName: creatorName) }
}
struct HomeFeed: Decodable {
    let loggedIn: Bool
    let accountName: String?
    let items: [FeedVideo]
    let page: Int
    let nextPage: Int?
}
struct CommentItem: Codable, Identifiable {
    let id: String, creatorId: String, creatorName: String
    let avatar: String?
    let message: String
    let createdAt: Double
    let likes: Int, replyCount: Int
    let replies: [CommentItem]
}
struct CommentPage: Decodable {
    let bvid: String
    let items: [CommentItem]
    let total: Int
    let nextPage: Int?
}
struct CommentReceipt: Decodable { let bvid: String; let message: String }
