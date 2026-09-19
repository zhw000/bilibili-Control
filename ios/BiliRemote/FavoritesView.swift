import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var model: RemoteModel
    @State private var folders: [FavoriteFolder] = []
    @State private var accountName = ""
    @State private var loading = false
    @State private var failure: String?
    @State private var generation = UUID()
    var body: some View {
        List {
            ConnectionNotice()
            if !accountName.isEmpty { Text("\(accountName) 的收藏夹").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(folders) { folder in
                NavigationLink { FavoriteVideosView(folder: folder) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "folder.fill").font(.title2).foregroundStyle(Color.biliPink)
                        VStack(alignment: .leading, spacing: 5) { Text(folder.title).font(.headline); Text("\(folder.count) 个收藏").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 8)
                }
            }
            if loading { ProgressView("读取收藏夹…") }
            if let failure { Text(failure).foregroundStyle(.secondary); Button("重试") { Task { await load() } }.disabled(!model.ready) }
            if model.ready && !loading && failure == nil && folders.isEmpty { ContentUnavailableView("还没有收藏夹", systemImage: "star", description: Text("这里显示电脑 Chrome 当前登录账号的收藏。")) }
        }.navigationTitle("我的收藏").listStyle(.plain)
            .task(id: model.ready) { await load() }
            .refreshable { await load() }
    }
    private func load() async {
        let ticket = UUID(); generation = ticket
        guard model.ready else { loading = false; return }
        loading = true; failure = nil
        defer { if generation == ticket { loading = false } }
        do {
            let result: FavoriteFolders = try await model.transport.request("favorites.folders")
            guard generation == ticket, !Task.isCancelled else { return }
            folders = result.items; accountName = result.accountName
        } catch { if generation == ticket && !Task.isCancelled { failure = error.localizedDescription } }
    }
}

struct FavoriteVideosView: View {
    let folder: FavoriteFolder
    @EnvironmentObject private var model: RemoteModel
    @State private var videos: [VideoItem] = []
    @State private var query = ""
    @State private var keyword = ""
    @State private var nextPage: Int?
    @State private var loading = false
    @State private var failure: String?
    @State private var generation = UUID()
    var body: some View {
        List {
            ConnectionNotice()
            Button { model.startQueue(QueueSource(kind: "favorites", folderId: folder.id, keyword: keyword)) } label: {
                Label(keyword.isEmpty ? "播放整个收藏夹" : "播放搜索结果", systemImage: "play.fill")
            }.buttonStyle(.borderedProminent).disabled(!model.ready || videos.isEmpty || loading)
            ForEach(videos) { VideoRow(video: $0) }
            if let failure { Text(failure).foregroundStyle(.secondary); Button("重试") { Task { await load(reset: false) } }.disabled(!model.ready) }
            if loading { ProgressView("读取收藏视频…") }
            if !loading && failure == nil && model.ready && videos.isEmpty { ContentUnavailableView("暂无视频", systemImage: "star", description: Text("收藏夹中没有匹配的视频，音频等内容暂不显示。")) }
            if nextPage != nil && !loading { Button("加载更多") { Task { await load(reset: false) } }.disabled(!model.ready) }
        }.navigationTitle(folder.title).navigationBarTitleDisplayMode(.inline).listStyle(.plain)
            .searchable(text: $query, prompt: "搜索这个收藏夹")
            .onSubmit(of: .search) { keyword = query.trimmingCharacters(in: .whitespacesAndNewlines) }
            .onChange(of: query) { _, value in if value.isEmpty { keyword = "" } }
            .task(id: "\(model.ready)-\(keyword)") { await load(reset: true) }
            .refreshable { await load(reset: true) }
    }
    private func load(reset: Bool) async {
        if loading && !reset { return }
        let ticket = UUID(); generation = ticket
        guard model.ready else { loading = false; return }
        loading = true; failure = nil
        let page = reset ? 1 : nextPage ?? 1
        if reset { videos = []; nextPage = nil }
        defer { if generation == ticket { loading = false } }
        do {
            let result: PageResult<VideoItem> = try await model.transport.request("favorites.videos", params: ["folderId": .string(folder.id), "keyword": .string(keyword), "page": .number(Double(page))])
            guard generation == ticket, !Task.isCancelled else { return }
            videos.append(contentsOf: result.items.filter { item in !videos.contains(where: { $0.id == item.id }) }); nextPage = result.nextPage
        } catch { if generation == ticket && !Task.isCancelled { failure = error.localizedDescription } }
    }
}
