import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: RemoteModel
    @State private var videos: [FeedVideo] = []
    @State private var accountName: String?
    @State private var loggedIn = true
    @State private var batch = 0
    @State private var nextPage: Int?
    @State private var loading = false
    @State private var failure: String?
    @State private var generation = UUID()
    private let columns = [GridItem(.adaptive(minimum: 158), spacing: 12, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ConnectionNotice()
                if let accountName { Text("\(accountName) 的首页推荐").font(.subheadline).foregroundStyle(.secondary) }
                else if !loggedIn { Label("电脑 Chrome 尚未登录哔哩哔哩，当前是通用推荐。登录后下拉刷新，即可看到为你推荐的内容。", systemImage: "person.crop.circle.badge.questionmark").font(.footnote).foregroundStyle(.secondary) }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(videos) { video in
                        FeedCard(video: video).onAppear { if video.id == videos.last?.id && nextPage != nil && failure == nil { Task { await load(reset: false) } } }
                    }
                }
                if loading { ProgressView("正在获取推荐…").frame(maxWidth: .infinity).padding(.vertical, 12) }
                if let failure {
                    VStack(spacing: 10) {
                        Text(failure).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("重试") { Task { await load(reset: videos.isEmpty) } }.disabled(!model.ready)
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                if model.ready && !loading && failure == nil && videos.isEmpty { ContentUnavailableView("暂时没有推荐", systemImage: "house", description: Text("下拉刷新，或稍后再试。")) }
                if nextPage != nil && !loading && failure == nil && !videos.isEmpty { Button("加载更多") { Task { await load(reset: false) } }.frame(maxWidth: .infinity).disabled(!model.ready) }
            }.padding(.horizontal, 16).padding(.vertical, 12)
        }
        .navigationTitle("首页")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await load(reset: true) } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("换一换").disabled(!model.ready || loading)
            }
        }
        .refreshable { await load(reset: true) }
        .task(id: model.ready) { if videos.isEmpty { await load(reset: true) } }
    }

    private func load(reset: Bool) async {
        if loading && !reset { return }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-state") { videos = FeedVideo.previews; accountName = "界面测试"; loggedIn = true; nextPage = nil; return }
        #endif
        let ticket = UUID(); generation = ticket
        guard model.ready else { loading = false; return }
        loading = true; failure = nil
        // Every request fetches a new batch, like pressing “换一换” on the computer's homepage.
        batch = batch >= 10000 ? 1 : batch + 1
        let page = batch
        if reset { videos = []; nextPage = nil }
        defer { if generation == ticket { loading = false } }
        do {
            let result: HomeFeed = try await model.transport.request("home.feed", params: ["page": .number(Double(page))])
            guard generation == ticket, !Task.isCancelled else { return }
            videos.append(contentsOf: result.items.filter { item in !videos.contains(where: { $0.id == item.id }) })
            accountName = result.accountName; loggedIn = result.loggedIn; nextPage = result.nextPage
        } catch {
            guard generation == ticket, !Task.isCancelled else { return }
            failure = (error as? RemoteFailure)?.code == "unknown_method" ? "请更新电脑助手和 Chrome 扩展，以显示首页推荐。" : error.localizedDescription
        }
    }
}

private struct FeedCard: View {
    let video: FeedVideo
    @EnvironmentObject private var model: RemoteModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.play(video.video) } label: {
                VStack(alignment: .leading, spacing: 7) {
                    CoverView(url: video.cover)
                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                        .overlay(alignment: .bottom) { stats }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text(video.title).font(.subheadline.weight(.medium)).lineLimit(2, reservesSpace: true).multilineTextAlignment(.leading)
                }.foregroundStyle(.primary).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!model.ready).accessibilityIdentifier("feedItem-\(video.bvid)")
            HStack(spacing: 5) {
                if let reason = video.reason {
                    Text(reason).font(.caption2.weight(.medium)).foregroundStyle(.orange).lineLimit(1)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .overlay { RoundedRectangle(cornerRadius: 3).stroke(Color.orange.opacity(0.6), lineWidth: 1) }
                        .layoutPriority(1)
                }
                if let id = video.creatorId, let name = video.creatorName, !name.isEmpty {
                    NavigationLink { CreatorView(creator: CreatorItem(id: id, name: name, url: "https://space.bilibili.com/\(id)")) } label: { Text(name).lineLimit(1) }.buttonStyle(.plain)
                }
                if let publishedAt = video.publishedAt { Text("· \(Date(timeIntervalSince1970: publishedAt).formatted(.relative(presentation: .named)))").lineLimit(1).layoutPriority(1) }
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
    private var stats: some View {
        // Numbers keep their natural width; narrow cards drop the danmaku count, then the view count.
        ViewThatFits(in: .horizontal) {
            statsRow(views: video.views, danmaku: video.danmaku)
            statsRow(views: video.views, danmaku: nil)
            statsRow(views: nil, danmaku: nil)
        }
        .font(.caption2.monospacedDigit()).foregroundStyle(.white).lineLimit(1)
        .padding(.horizontal, 7).padding(.top, 14).padding(.bottom, 5)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom))
    }
    private func statsRow(views: Int?, danmaku: Int?) -> some View {
        HStack(spacing: 8) {
            if let views { stat("play.rectangle", views) }
            if let danmaku { stat("text.bubble", danmaku) }
            Spacer(minLength: 4)
            if let duration = video.duration { Text(Timecode.format(duration)).fixedSize() }
        }
    }
    private func stat(_ icon: String, _ count: Int) -> some View {
        HStack(spacing: 2) { Image(systemName: icon); Text(count.formatted(.number.notation(.compactName))) }.fixedSize()
    }
}

#if DEBUG
extension FeedVideo {
    static let previews: [FeedVideo] = (1...12).map { number in
        let title: String = number == 1 ? "保持好奇，探索每一个新世界，一起出发去看山川、森林与海洋" : "推荐视频 \(number) · 周末和朋友一起发现新的风景"
        let reason: String? = number % 4 == 1 ? "已关注" : (number % 4 == 2 ? "\(number)万点赞" : nil)
        let publishedAt: Double = Date().timeIntervalSince1970 - Double(number * 7_200)
        return FeedVideo(bvid: "BVHome\(number)", title: title, url: "https://www.bilibili.com/", cover: "preview-cover", duration: Double(180 + number * 37), creatorId: "1", creatorName: "界面测试", views: number * 12_000, danmaku: number * 37, publishedAt: publishedAt, reason: reason)
    }
}
#endif
