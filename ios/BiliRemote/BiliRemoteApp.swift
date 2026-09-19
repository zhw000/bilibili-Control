import SwiftUI
import AppIntents

@main struct BiliRemoteApp: App {
    init() { PlaybackShortcuts.updateAppShortcutParameters() }
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
            NavigationStack { FavoritesView().safeAreaInset(edge: .bottom) { MiniPlayer() } }.tabItem { Label("收藏", systemImage: "star") }.tag(2)
            NavigationStack { DevicesView() }.tabItem { Label("设备", systemImage: "desktopcomputer") }.tag(3)
        }
    }
}
struct CoverView: View {
    let url: String?
    var body: some View {
        Rectangle().fill(Color.biliPink.opacity(0.10))
            .overlay {
                // Overlay content cannot enlarge the frame when a large image finishes loading.
                #if DEBUG
                if url == "preview-cover" { Image(uiImage: Self.previewImage).resizable().scaledToFill() }
                else { remoteImage }
                #else
                remoteImage
                #endif
            }.clipped()
    }
    private var remoteImage: some View {
        RemoteCoverImage(source: url)
    }
    #if DEBUG
    private static let previewImage = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 900)).image { context in
        UIColor(red: 0.16, green: 0.38, blue: 0.39, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
        UIColor(red: 0.83, green: 0.90, blue: 0.77, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 520, width: 1600, height: 380))
        UIColor(red: 0.96, green: 0.76, blue: 0.51, alpha: 1).setFill(); context.cgContext.fillEllipse(in: CGRect(x: 1150, y: 90, width: 250, height: 250))
        ("一起去看世界" as NSString).draw(at: CGPoint(x: 100, y: 290), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 100), .foregroundColor: UIColor.white])
    }
    #endif
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
                    CoverView(url: video.cover).frame(width: 112, height: 63).clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .bottomTrailing) { if let duration = video.duration { Text(Timecode.format(duration)).font(.caption2.monospacedDigit()).padding(4).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4)).foregroundStyle(.white).padding(5) } }
                    VStack(alignment: .leading, spacing: 6) { Text(video.title).font(.subheadline.weight(.medium)).lineLimit(3); if let reason = video.unavailableReason { Text(reason).font(.caption).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading)
                }.foregroundStyle(.primary)
            }.buttonStyle(.plain).disabled(!model.ready || video.unavailableReason != nil)
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
