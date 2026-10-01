import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var model: RemoteModel
    @State private var query = ""
    @State private var kind = "videos"
    @State private var videos: [VideoItem] = []
    @State private var creators: [CreatorItem] = []
    @State private var media: [CollectionItem] = []
    @State private var nextPage: Int?
    @State private var loading = false
    @State private var searched = false
    @State private var generation = UUID()
    @State private var failure: String?
    var body: some View {
        List {
            ConnectionNotice().listRowSeparator(.hidden)
            Picker("搜索类型", selection: $kind) { Text("视频").tag("videos"); Text("影视").tag("media"); Text("UP 主").tag("creators") }.pickerStyle(.segmented).listRowSeparator(.hidden)
            if kind == "media" { Text("电影、电视剧、纪录片等正版影视，进入片目后选集播放。").font(.footnote).foregroundStyle(.secondary).listRowSeparator(.hidden) }
            if !searched { ContentUnavailableView("想看点什么？", systemImage: "sparkles.tv", description: Text("在手机找到喜欢的内容，\n让电脑的大屏开始播放。")).listRowSeparator(.hidden) }
            if let failure { Text(failure).foregroundStyle(.secondary) }
            if kind == "videos" { ForEach(videos) { VideoRow(video: $0) } }
            else if kind == "media" {
                ForEach(media) { item in
                    NavigationLink { SeasonView(season: item) } label: {
                        HStack(spacing: 12) {
                            CoverView(url: item.cover).frame(width: 78, height: 104).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title).font(.headline)
                                if let detail = item.description { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                                Text("查看选集").font(.caption).foregroundStyle(Color.biliPink)
                            }
                        }.padding(.vertical, 6)
                    }
                }
            }
            else { ForEach(creators) { creator in NavigationLink { CreatorView(creator: creator) } label: { HStack(spacing: 12) { CoverView(url: creator.avatar).frame(width: 48, height: 48).clipShape(Circle()); VStack(alignment: .leading, spacing: 5) { Text(creator.name).font(.headline); Text(creator.description ?? "进入主页查看投稿和合集").font(.caption).foregroundStyle(.secondary).lineLimit(2) } }.padding(.vertical, 6) } } }
            if searched && !loading && failure == nil && videos.isEmpty && creators.isEmpty && media.isEmpty { ContentUnavailableView.search(text: query) }
            if loading { HStack { Spacer(); ProgressView("正在电脑上查找…"); Spacer() }.listRowSeparator(.hidden) }
            if nextPage != nil && !loading { Button("加载更多") { Task { await load(reset: false) } }.frame(maxWidth: .infinity) }
        }.listStyle(.plain).navigationTitle("发现")
            .searchable(text: $query, prompt: "搜索视频、影视或 UP 主").onSubmit(of: .search) { Task { await load(reset: true) } }
            .onChange(of: kind) { _, _ in if searched { Task { await load(reset: true) } } }
    }
    private func load(reset: Bool) async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }
        let ticket = UUID(); generation = ticket; loading = true; searched = true; failure = nil
        let category = kind, page = reset ? 1 : nextPage ?? 1
        if reset { videos = []; creators = []; media = []; nextPage = nil }
        do {
            let params: [String: JSONValue] = ["query": .string(text), "kind": .string(category), "page": .number(Double(page))]
            if category == "videos" { let result: PageResult<VideoItem> = try await model.transport.request("search", params: params); guard generation == ticket else { return }; videos.append(contentsOf: result.items.filter { item in !videos.contains(where: { $0.id == item.id }) }); nextPage = result.nextPage }
            else if category == "media" { let result: PageResult<CollectionItem> = try await model.transport.request("search", params: params); guard generation == ticket else { return }; media.append(contentsOf: result.items.filter { item in !media.contains(where: { $0.id == item.id }) }); nextPage = result.nextPage }
            else { let result: PageResult<CreatorItem> = try await model.transport.request("search", params: params); guard generation == ticket else { return }; creators.append(contentsOf: result.items.filter { item in !creators.contains(where: { $0.id == item.id }) }); nextPage = result.nextPage }
        } catch { if generation == ticket { failure = error.localizedDescription } }
        if generation == ticket { loading = false }
    }
}
struct SeasonView: View {
    let season: CollectionItem
    @EnvironmentObject private var model: RemoteModel
    @State private var episodes: [VideoItem] = []
    @State private var loading = false
    @State private var failure: String?
    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 12) {
                Text(season.title).font(.title2.bold())
                if let detail = season.description { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
                Text("观看权限与电脑 B 站账号一致；会员或付费内容请先在电脑确认。").font(.footnote).foregroundStyle(.secondary)
                Button { play(from: nil) } label: { Label("从头播放", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).disabled(!model.ready || episodes.isEmpty)
            }.padding(.vertical, 10)
            ForEach(episodes) { episode in
                Button { play(from: episode.bvid) } label: {
                    HStack {
                        Text(episode.title).foregroundStyle(.primary)
                        Spacer()
                        if let badge = episode.creatorName { Text(badge).font(.caption).foregroundStyle(.secondary) }
                        Image(systemName: "play.circle").foregroundStyle(Color.biliPink)
                    }.padding(.vertical, 8)
                }.disabled(!model.ready)
            }
            if loading { ProgressView("读取正片选集…") }
            if let failure { Text(failure).foregroundStyle(.secondary); Button("重新加载") { Task { await load() } } }
        }.listStyle(.plain).navigationTitle("影视选集").navigationBarTitleDisplayMode(.inline).task { await load() }
    }
    private func play(from bvid: String?) { model.startQueue(QueueSource(kind: "season", url: season.url, startBvid: bvid)) }
    private func load() async {
        guard !loading else { return }; loading = true; failure = nil; defer { loading = false }
        do {
            let result: PageResult<VideoItem> = try await model.transport.request("season.episodes", params: ["url": .string(season.url), "page": .number(1)])
            episodes = result.items
        } catch { failure = error.localizedDescription }
    }
}
struct CreatorView: View {
    let creator: CreatorItem
    @EnvironmentObject private var model: RemoteModel
    @State private var category = "videos"
    @State private var order = "newest"
    @State private var videos: [VideoItem] = []
    @State private var collections: [CollectionItem] = []
    @State private var nextPage: Int?
    @State private var loading = false
    @State private var failure: String?
    @State private var generation = UUID()
    @State private var profile: CreatorProfile?
    @State private var profileError: String?
    @State private var query = ""
    @State private var keyword = ""
    var body: some View {
        List {
            ConnectionNotice()
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) { CoverView(url: profile?.avatar ?? creator.avatar).frame(width: 64, height: 64).clipShape(Circle()); VStack(alignment: .leading, spacing: 5) { Text(profile?.name ?? creator.name).font(.title2.bold()); Text("UP 主 · \(creator.id)").font(.caption).foregroundStyle(.secondary) } }
                if let description = profile?.description ?? creator.description, !description.isEmpty { Text(description).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled) }
                if let profile {
                    if !profile.verified.isEmpty { Label(profile.verified, systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(Color.biliPink) }
                    HStack(spacing: 18) {
                        stat("粉丝", profile.followers); stat("关注", profile.following); stat("投稿", profile.videoCount); stat("获赞", profile.likes)
                    }
                    Text("等级 Lv.\(profile.level)").font(.caption2).foregroundStyle(.secondary)
                }
                if let profileError { Text(profileError).font(.caption).foregroundStyle(.secondary); Button("重试主页资料") { Task { await loadProfile() } }.font(.caption).disabled(!model.ready) }
                if let url = URL(string: "https://space.bilibili.com/\(creator.id)") { ShareLink(item: url) { Label("分享主页", systemImage: "square.and.arrow.up").font(.caption) } }
            }.padding(.vertical, 8).listRowSeparator(.hidden)
            Picker("内容类型", selection: $category) { Text("全部投稿").tag("videos"); Text("合集和系列").tag("collections") }.pickerStyle(.segmented)
            if category == "videos" {
                HStack { Picker("顺序", selection: $order) { Text("最新优先").tag("newest"); Text("最早优先").tag("oldest"); Text("最多播放").tag("popular") }; Spacer(); Button { model.startQueue(QueueSource(kind: "creator", creatorId: creator.id, order: order, keyword: keyword)) } label: { Label(keyword.isEmpty ? "全部播放" : "播放结果", systemImage: "play.fill") }.buttonStyle(.borderedProminent).disabled(!model.ready || videos.isEmpty || loading) }
                ForEach(videos) { VideoRow(video: $0) }
            } else {
                ForEach(collections) { collection in NavigationLink { CollectionView(collection: collection) } label: { HStack { CoverView(url: collection.cover).frame(width: 110, height: 70).clipShape(RoundedRectangle(cornerRadius: 10)); VStack(alignment: .leading, spacing: 5) { Text(collection.title).font(.headline); if let count = collection.count { Text("\(count) 个视频").font(.caption).foregroundStyle(.secondary) } } }.padding(.vertical, 5) } }
            }
            if let failure { Text(failure).foregroundStyle(.secondary); Button("重新加载") { Task { await load(reset: true) } } }
            if loading { ProgressView("读取主页…").frame(maxWidth: .infinity) }
            if model.ready && !loading && failure == nil && (category == "videos" ? videos.isEmpty : collections.isEmpty) { ContentUnavailableView("这里还没有内容", systemImage: "tray") }
            if nextPage != nil && !loading { Button("加载更多") { Task { await load(reset: false) } } }
        }.listStyle(.plain).navigationTitle("UP 主主页").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索这位 UP 主的投稿")
            .onSubmit(of: .search) { category = "videos"; keyword = query.trimmingCharacters(in: .whitespacesAndNewlines) }
            .onChange(of: query) { _, value in if value.isEmpty { keyword = "" } }
            .task(id: "\(model.ready)-\(category)-\(order)-\(keyword)") { await load(reset: true) }
            .task(id: model.ready) { await loadProfile() }
            .refreshable { await loadProfile(); await load(reset: true) }
    }
    private func stat(_ title: String, _ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(count.formatted(.number.notation(.compactName))).font(.subheadline.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }
    }
    private func loadProfile() async {
        guard model.ready else { return }
        do { let result: CreatorProfile = try await model.transport.request("creator.profile", params: ["creatorId": .string(creator.id)]); guard !Task.isCancelled else { return }; profile = result; profileError = nil }
        catch { if !Task.isCancelled { profileError = error.localizedDescription } }
    }
    private func load(reset: Bool) async {
        if loading && !reset { return }
        let ticket = UUID(); generation = ticket; loading = true; failure = nil
        guard model.ready else { loading = false; return }
        let mode = category, page = reset ? 1 : nextPage ?? 1
        if reset { videos = []; collections = []; nextPage = nil }
        do {
            let params: [String: JSONValue] = ["creatorId": .string(creator.id), "order": .string(order), "keyword": .string(keyword), "page": .number(Double(page))]
            if mode == "videos" { let result: PageResult<VideoItem> = try await model.transport.request("creator.videos", params: params); guard ticket == generation else { return }; videos.append(contentsOf: result.items.filter { item in !videos.contains(where: { $0.id == item.id }) }); nextPage = result.nextPage }
            else { let result: PageResult<CollectionItem> = try await model.transport.request("creator.collections", params: params); guard ticket == generation else { return }; collections.append(contentsOf: result.items.filter { item in !collections.contains(where: { $0.id == item.id }) }); nextPage = result.nextPage }
        } catch { if ticket == generation { failure = error.localizedDescription } }
        if ticket == generation { loading = false }
    }
}
struct CollectionView: View {
    let collection: CollectionItem
    @EnvironmentObject private var model: RemoteModel
    @State private var videos: [VideoItem] = []
    @State private var nextPage: Int?
    @State private var loading = false
    @State private var failure: String?
    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 15) { Text(collection.title).font(.title2.bold()); Button { model.startQueue(QueueSource(kind: "collection", url: collection.url)) } label: { Label("全部播放", systemImage: "play.fill") }.buttonStyle(.borderedProminent).disabled(!model.ready) }.padding(.vertical, 10)
            ForEach(videos) { VideoRow(video: $0) }
            if let failure { Text(failure).foregroundStyle(.secondary); Button("重新加载") { Task { await load(reset: true) } } }
            if loading { ProgressView("读取合集…") }
            if !loading && failure == nil && videos.isEmpty { ContentUnavailableView("合集还没有视频", systemImage: "tray") }
            if nextPage != nil && !loading { Button("加载更多") { Task { await load(reset: false) } } }
        }.listStyle(.plain).navigationTitle("合集和系列").navigationBarTitleDisplayMode(.inline).task { await load(reset: true) }
    }
    private func load(reset: Bool) async {
        guard !loading else { return }; loading = true; failure = nil; defer { loading = false }
        let page = reset ? 1 : nextPage ?? 1
        do { let result: PageResult<VideoItem> = try await model.transport.request("collection.videos", params: ["url": .string(collection.url), "page": .number(Double(page))]); if reset { videos = [] }; videos.append(contentsOf: result.items.filter { item in !videos.contains(where: { $0.id == item.id }) }); nextPage = result.nextPage }
        catch { failure = error.localizedDescription }
    }
}
