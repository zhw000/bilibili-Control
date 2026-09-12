import SwiftUI

@main struct BiliRemoteApp: App {
    @StateObject private var model = RemoteModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).tint(.biliPink)
                .onOpenURL { url in Task { await model.pair(url.absoluteString) } }
                .onChange(of: scenePhase) { _, phase in if phase == .active { model.connect() } else if phase == .background { model.background() } }
                .task { model.connect() }
                .alert("操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("知道了") { model.error = nil } } message: { Text(model.error ?? "") }
        }
    }
}
extension Color { static let biliPink = Color(red: 0.91, green: 0.34, blue: 0.48) }
struct RootView: View {
    @EnvironmentObject private var model: RemoteModel
    var body: some View {
        TabView(selection: $model.selectedTab) {
            NavigationStack { SearchView().safeAreaInset(edge: .bottom) { MiniPlayer() } }.tabItem { Label("发现", systemImage: "magnifyingglass") }.tag(0)
            NavigationStack { PlayerView() }.tabItem { Label("播放", systemImage: "play.circle") }.tag(1)
            NavigationStack { QueueView().safeAreaInset(edge: .bottom) { MiniPlayer() } }.tabItem { Label("队列", systemImage: "list.bullet.rectangle") }.tag(2)
            NavigationStack { DevicesView() }.tabItem { Label("设备", systemImage: "desktopcomputer") }.tag(3)
        }
    }
}
struct CoverView: View {
    let url: String?
    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() } placeholder: { Rectangle().fill(Color.biliPink.opacity(0.10)).overlay { Image(systemName: "play.rectangle.fill").font(.title2).foregroundStyle(Color.biliPink.opacity(0.5)) } }
            .clipped()
    }
}
struct MiniPlayer: View {
    @EnvironmentObject private var model: RemoteModel
    var body: some View {
        if !model.snapshot.player.bvid.isEmpty {
            HStack(spacing: 12) {
                Button { model.selectedTab = 1 } label: {
                    HStack(spacing: 12) { CoverView(url: model.currentCover).frame(width: 54, height: 38).clipShape(RoundedRectangle(cornerRadius: 7)); VStack(alignment: .leading, spacing: 3) { Text(model.snapshot.player.title).font(.subheadline.weight(.medium)).lineLimit(1); Text(model.ready ? "正在电脑上播放" : "连接已断开").font(.caption).foregroundStyle(.secondary) } }.foregroundStyle(.primary)
                }.buttonStyle(.plain)
                Spacer(minLength: 0)
                Button { model.control(model.snapshot.player.paused ? "play" : "pause") } label: { Image(systemName: model.snapshot.player.paused ? "play.fill" : "pause.fill").frame(width: 44, height: 44) }.disabled(!model.ready).accessibilityLabel(model.snapshot.player.paused ? "继续播放" : "暂停")
            }.padding(.horizontal, 16).padding(.vertical, 6).background(.regularMaterial)
        }
    }
}
struct VideoRow: View {
    let video: VideoItem
    @EnvironmentObject private var model: RemoteModel
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { model.play(video) } label: {
                HStack(alignment: .top, spacing: 12) {
                    CoverView(url: video.cover).frame(width: 125, height: 78).clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .bottomTrailing) { if let duration = video.duration { Text(Timecode.format(duration)).font(.caption2.monospacedDigit()).padding(4).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(.white).padding(5) } }
                    VStack(alignment: .leading, spacing: 6) { Text(video.title).font(.subheadline.weight(.medium)).lineLimit(3); if let reason = video.unavailableReason { Text(reason).font(.caption).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading)
                }.foregroundStyle(.primary)
            }.buttonStyle(.plain)
            if let id = video.creatorId, let name = video.creatorName, !name.isEmpty {
                NavigationLink { CreatorView(creator: CreatorItem(id: id, name: name, url: "https://space.bilibili.com/\(id)")) } label: { Label(name, systemImage: "person.crop.circle").font(.caption).foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
        }.padding(.vertical, 5)
    }
}
struct ConnectionNotice: View {
    @EnvironmentObject private var model: RemoteModel
    var body: some View {
        if !model.ready {
            Button { model.selectedTab = 3 } label: { Label(model.connected ? "请打开 Chrome 并连接扩展" : "连接电脑，开始遥控", systemImage: "wifi.exclamationmark").font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).padding(14).background(Color.biliPink.opacity(0.08), in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
        }
    }
}
