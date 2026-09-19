import SwiftUI

@main struct BiliRemoteWatchApp: App {
    @StateObject private var remote = WatchRemoteModel()
    var body: some Scene { WindowGroup { WatchPlayerView().environmentObject(remote).tint(.pink) } }
}

struct WatchPlayerView: View {
    @EnvironmentObject private var remote: WatchRemoteModel
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(remote.state.computerName).font(.caption).foregroundStyle(.secondary)
                Text(remote.state.title).font(.headline).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                if let lastUpdated = remote.lastUpdated { HStack { Text("上次同步"); Text(lastUpdated, style: .time) }.font(.caption2).foregroundStyle(.secondary) }
                if !remote.reachable { Text("请靠近 iPhone 并打开手机上的哔哩遥控").font(.caption).foregroundStyle(.secondary) }
                else if !remote.state.connected { Text("尚未连接电脑，点按刷新状态重连").font(.caption).foregroundStyle(.secondary) }
                ProgressView(value: min(max(remote.state.currentTime, 0), max(remote.state.duration, 1)), total: max(remote.state.duration, 1))
                HStack { Text(Timecode.format(remote.state.currentTime)); Spacer(); Text(Timecode.format(remote.state.duration)) }.font(.caption2.monospacedDigit())
                HStack {
                    action(.previous, icon: "backward.end.fill").disabled(!remote.state.canPrevious)
                    action(remote.state.paused ? .play : .pause, icon: remote.state.paused ? "play.fill" : "pause.fill").tint(.pink)
                    action(.next, icon: "forward.end.fill").disabled(!remote.state.canNext)
                }
                HStack { action(.backward, icon: "gobackward.10"); action(.forward, icon: "goforward.10") }
                HStack { action(.volumeDown, icon: "speaker.minus.fill"); Text("\(Int(remote.state.volume * 100))%").font(.caption.monospacedDigit()); action(.volumeUp, icon: "speaker.plus.fill") }
                if remote.busy { ProgressView("正在连接电脑…").font(.caption) }
                if let error = remote.error { Text(error).font(.caption).foregroundStyle(.orange) }
                Button("刷新状态") { remote.send(.refresh) }.disabled(!remote.reachable || remote.busy)
            }.padding(.horizontal, 4)
        }.navigationTitle("哔哩遥控")
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    remote.send(.refresh, silently: true)
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                }
            }
    }
    private func action(_ action: RemoteAction, icon: String) -> some View {
        Button { remote.send(action) } label: { Image(systemName: icon).frame(maxWidth: .infinity, minHeight: 36) }
            .accessibilityLabel(action.title).disabled(!remote.reachable || remote.busy)
    }
}
