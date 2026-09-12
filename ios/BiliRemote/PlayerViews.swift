import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var model: RemoteModel
    @State private var seeking = false
    @State private var seekValue: Double = 0
    @State private var showTime = false
    @State private var timeText = ""
    private var player: PlayerState { model.snapshot.player }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ConnectionNotice()
                if player.bvid.isEmpty { ContentUnavailableView("大屏，准备就绪", systemImage: "play.desktopcomputer", description: Text("从发现页选择视频，\n或在设备页选择已有的播放标签页。")).padding(.vertical, 55) }
                else {
                    CoverView(url: model.currentCover).aspectRatio(16 / 10, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 8) { Text(player.title).font(.title2.bold()); HStack { Label(model.snapshot.computerName, systemImage: "desktopcomputer"); if player.partCount > 1 { Text("P\(player.part) / \(player.partCount)") } }.font(.caption).foregroundStyle(.secondary) }
                    VStack(spacing: 6) {
                        Slider(value: $seekValue, in: 0...max(player.duration, 1)) { editing in seeking = editing; if !editing { model.control("seek", value: .number(seekValue)) } }.disabled(!model.ready || player.duration <= 0)
                        HStack { Button { timeText = Timecode.format(player.currentTime); showTime = true } label: { Text(Timecode.format(seeking ? seekValue : player.currentTime)) }; Spacer(); Text(Timecode.format(player.duration)) }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack {
                        controlButton("backward.end.fill", "上一个视频") { model.execute("queue.previous") }
                        Spacer(); controlButton("gobackward.10", "后退十秒") { model.control("seekBy", value: .number(-10)) }; Spacer()
                        Button { model.control(player.paused ? "play" : "pause") } label: { Image(systemName: player.paused ? "play.fill" : "pause.fill").font(.system(size: 27, weight: .semibold)).frame(width: 76, height: 76).foregroundStyle(.white).background(Color.biliPink, in: Circle()) }.accessibilityLabel(player.paused ? "继续播放" : "暂停")
                        Spacer(); controlButton("goforward.10", "前进十秒") { model.control("seekBy", value: .number(10)) }; Spacer()
                        controlButton("forward.end.fill", "下一个视频") { model.execute("queue.next") }
                    }.disabled(!model.ready)
                    HStack(spacing: 12) {
                        Menu { ForEach([0.5, 0.75, 1, 1.25, 1.5, 1.75, 2], id: \.self) { rate in Button("\(rate.formatted())×") { model.control("rate", value: .number(rate)) } } } label: { Text("\(player.rate.formatted())× 倍速").frame(maxWidth: .infinity) }
                        Button { model.control("danmaku", value: .bool(!player.danmaku)) } label: { Label("弹幕", systemImage: player.danmaku ? "text.bubble.fill" : "text.bubble").frame(maxWidth: .infinity) }
                        Button { model.control("fullscreen", value: .bool(!player.fullscreen)) } label: { Image(systemName: player.fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").frame(maxWidth: .infinity) }.accessibilityLabel(player.fullscreen ? "退出全屏" : "进入全屏")
                    }.buttonStyle(.bordered).disabled(!model.ready)
                    VStack(spacing: 22) {
                        VolumeControl(title: "视频音量", subtitle: "哔哩哔哩播放器", value: player.volume, muted: player.muted, enabled: model.ready, set: { model.control("volume", value: .number($0)) }, mute: { model.control("mute", value: .bool(!player.muted)) })
                        Divider()
                        VolumeControl(title: "电脑音量", subtitle: model.snapshot.systemVolume.deviceName, value: model.snapshot.systemVolume.value, muted: model.snapshot.systemVolume.muted, enabled: model.connected && model.snapshot.systemVolume.available, set: { model.execute("system.volume", ["value": .number($0)]) }, mute: { model.execute("system.mute", ["value": .bool(!model.snapshot.systemVolume.muted)]) })
                    }.padding(20).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    if let message = model.snapshot.queue.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    if model.snapshot.queue.canResume { Button("继续上次队列") { model.execute("queue.resume") }.buttonStyle(.borderedProminent).disabled(!model.ready) }
                }
            }.padding(22)
        }.background(Color(.systemGroupedBackground)).navigationTitle("正在播放")
            .onChange(of: player.currentTime, initial: true) { _, value in if !seeking { seekValue = min(value, max(player.duration, 1)) } }
            .alert("跳转到指定时间", isPresented: $showTime) { TextField("mm:ss 或 hh:mm:ss", text: $timeText).keyboardType(.numbersAndPunctuation); Button("跳转") { do { model.control("seek", value: .number(try Timecode.parse(timeText))) } catch { model.error = error.localizedDescription } }; Button("取消", role: .cancel) {} } message: { Text("例如 12:30 或 1:02:30") }
    }
    private func controlButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View { Button(action: action) { Image(systemName: icon).font(.system(size: 23)).frame(minWidth: 34, minHeight: 48) }.accessibilityLabel(label).foregroundStyle(.primary) }
}
struct VolumeControl: View {
    let title: String, subtitle: String
    let value: Double, muted: Bool, enabled: Bool
    let set: (Double) -> Void, mute: () -> Void
    @State private var editing = false
    @State private var localValue: Double = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline.weight(.semibold)); Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer(); Text("\(Int((editing ? localValue : value) * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            HStack { Button(action: mute) { Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 32, height: 36) }.accessibilityLabel(muted ? "取消\(title)静音" : "\(title)静音"); Slider(value: $localValue, in: 0...1) { changed in editing = changed; if !changed { set(localValue) } } }.disabled(!enabled)
        }.onChange(of: value, initial: true) { _, changed in if !editing { localValue = max(0, min(1, changed)) } }
    }
}
struct QueueView: View {
    @EnvironmentObject private var model: RemoteModel
    var body: some View {
        List {
            if model.snapshot.queue.items.isEmpty { ContentUnavailableView("还没有播放队列", systemImage: "list.bullet.rectangle", description: Text("进入 UP 主或合集，选择全部播放。")) }
            else {
                Section {
                    if let message = model.snapshot.queue.message { Text(message).foregroundStyle(.secondary) }
                    HStack { Text("已载入 \(model.snapshot.queue.items.count) 个视频").font(.subheadline); Spacer(); if model.snapshot.queue.active { Text("连续播放中").font(.caption).foregroundStyle(Color.biliPink) } }
                    if model.snapshot.queue.nextPage != nil { Text("后续视频将在播放时自动加载。").font(.caption).foregroundStyle(.secondary) }
                    if model.snapshot.queue.canResume { Button("继续播放") { model.execute("queue.resume") }.disabled(!model.ready) }
                }
                ForEach(Array(model.snapshot.queue.items.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) { Text(String(index + 1)).font(.caption.monospacedDigit()).foregroundStyle(index == model.snapshot.queue.index ? Color.biliPink : .secondary).frame(width: 25); VStack(alignment: .leading, spacing: 6) { Text(item.title).font(.subheadline).lineLimit(2); if let reason = item.unavailableReason { Text(reason).font(.caption).foregroundStyle(.secondary) } }; Spacer(); if index == model.snapshot.queue.index { Image(systemName: "waveform").foregroundStyle(Color.biliPink) } }.padding(.vertical, 8)
                }
            }
        }.navigationTitle("播放队列").toolbar { if model.snapshot.queue.active { Button("停止连播") { model.execute("queue.stop") }.disabled(!model.connected) } }
    }
}
