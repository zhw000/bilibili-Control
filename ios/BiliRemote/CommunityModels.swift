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
