import SwiftUI

struct PlayerView: View {
    @EnvironmentObject private var model: RemoteModel
    @State private var seeking = false
    @State private var seekValue: Double = 0
    @State private var showTime = false
    @State private var showVolume = false
    @State private var showQuality = false
    @State private var timeText = ""
    private var player: PlayerState { model.snapshot.player }
    private var hasNext: Bool {
        model.showsPlaylist ? model.snapshot.queue.index + 1 < model.snapshot.queue.items.count || model.snapshot.queue.nextPage != nil : !model.visibleRelatedVideos.isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ConnectionNotice()
                    if player.bvid.isEmpty {
                        ContentUnavailableView("大屏，准备就绪", systemImage: "play.desktopcomputer", description: Text("从发现页选择视频，\n或在设备页选择已有的播放标签页。")).padding(.vertical, 40)
                    } else {
                        CoverView(url: model.currentCover)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityElement(children: .ignore).accessibilityLabel("视频封面").accessibilityIdentifier("playerCover")
                        VStack(alignment: .leading, spacing: 7) {
                            Text(player.title).font(.title3.bold()).lineLimit(3).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("playerTitle")
                            HStack {
                                Label(model.snapshot.computerName, systemImage: "desktopcomputer").lineLimit(1)
                                if player.partCount > 1 { Text("P\(player.part) / \(player.partCount)").fixedSize() }
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                        progress
                        playbackControls
                        options
                        Button { showQuality = true } label: {
                            HStack(spacing: 12) {
                                Label("清晰度", systemImage: "4k.tv")
                                Spacer(minLength: 8)
                                Text(player.quality?.displayName ?? "选择清晰度").foregroundStyle(.secondary).lineLimit(1)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            }.font(.subheadline).padding(14).frame(maxWidth: .infinity, minHeight: 48)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).disabled(!model.ready).accessibilityIdentifier("videoQuality")
                        if player.bvid.hasPrefix("BV") { NavigationLink(value: VideoCommentsRoute(bvid: player.bvid)) {
                            Label("查看评论 / 发表评论", systemImage: "bubble.left.and.bubble.right").font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.bordered).disabled(!model.ready) }
                        volume
                        PlaybackListSection()
                    }
                }
                .frame(width: max(0, min(geometry.size.width - 32, 640)), alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }.accessibilityIdentifier("playerScroll")
        }
        .background(Color(.systemGroupedBackground)).navigationTitle("正在播放").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: VideoCommentsRoute.self) { route in CommentsView(bvid: route.bvid) }
        .sheet(isPresented: $showQuality) { QualityView().environmentObject(model).presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
        .task(id: model.relatedRequestKey) { await model.loadRelated() }
        .onChange(of: player.currentTime, initial: true) { _, value in if !seeking { seekValue = max(0, min(value, max(player.duration, 1))) } }
        .onChange(of: player.bvid) { _, _ in seeking = false; seekValue = max(0, min(player.currentTime, max(player.duration, 1))) }
        .alert("跳转到指定时间", isPresented: $showTime) {
            TextField("mm:ss 或 hh:mm:ss", text: $timeText).keyboardType(.numbersAndPunctuation)
            Button("跳转") { do { model.control("seek", value: .number(try Timecode.parse(timeText))) } catch { model.error = error.localizedDescription } }
            Button("取消", role: .cancel) {}
        } message: { Text("例如 12:30 或 1:02:30") }
    }

    private var progress: some View {
        VStack(spacing: 4) {
            Slider(value: $seekValue, in: 0...max(player.duration, 1)) { editing in
                seeking = editing
                if !editing { model.control("seek", value: .number(seekValue)) }
            }.disabled(!model.ready || player.duration <= 0).accessibilityLabel("播放进度")
            HStack {
                Button { timeText = Timecode.format(player.currentTime); showTime = true } label: { Text(Timecode.format(seeking ? seekValue : player.currentTime)) }
                    .accessibilityLabel("跳转时间").accessibilityIdentifier("currentTime")
                Spacer()
                Text(Timecode.format(player.duration)).accessibilityIdentifier("duration")
            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 0) {
            controlButton("backward.end.fill", "上一个视频") { model.execute("queue.previous") }
                .disabled(!model.showsPlaylist || model.snapshot.queue.index <= 0)
            Spacer(minLength: 0)
            controlButton("gobackward.10", "后退十秒") { model.control("seekBy", value: .number(-10)) }
            Spacer(minLength: 0)
            Button { model.control(player.paused ? "play" : "pause") } label: {
                Image(systemName: player.paused ? "play.fill" : "pause.fill").font(.system(size: 24, weight: .semibold))
                    .frame(width: 64, height: 64).foregroundStyle(.white).background(Color.biliPink, in: Circle())
            }.accessibilityLabel(player.paused ? "继续播放" : "暂停").accessibilityIdentifier("mainPlaybackButton")
            Spacer(minLength: 0)
            controlButton("goforward.10", "前进十秒") { model.control("seekBy", value: .number(10)) }
            Spacer(minLength: 0)
            controlButton("forward.end.fill", "下一个视频") { model.nextVideo() }.disabled(!hasNext)
        }.disabled(!model.ready)
    }

    private var options: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach([0.5, 0.75, 1, 1.25, 1.5, 1.75, 2], id: \.self) { rate in Button("\(rate.formatted())×") { model.control("rate", value: .number(rate)) } }
            } label: { Text("\(player.rate.formatted())×").frame(maxWidth: .infinity, minHeight: 32) }.accessibilityLabel("播放倍速")
            Button { model.control("danmaku", value: .bool(!player.danmaku)) } label: {
                Image(systemName: player.danmaku ? "text.bubble.fill" : "text.bubble").frame(maxWidth: .infinity, minHeight: 32)
            }.accessibilityLabel(player.danmaku ? "关闭弹幕" : "打开弹幕")
            Button { model.control("fullscreen", value: .bool(!player.fullscreen)) } label: {
                Image(systemName: player.fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").frame(maxWidth: .infinity, minHeight: 32)
            }.accessibilityLabel(player.fullscreen ? "退出全屏" : "进入全屏")
        }.buttonStyle(.bordered).disabled(!model.ready)
    }

    private var volume: some View {
        DisclosureGroup(isExpanded: $showVolume) {
            VStack(spacing: 18) {
                VolumeControl(title: "视频音量", subtitle: "哔哩哔哩播放器", value: player.volume, muted: player.muted, enabled: model.ready,
                              set: { model.control("volume", value: .number($0)) }, mute: { model.control("mute", value: .bool(!player.muted)) })
                Divider()
                VolumeControl(title: "电脑音量", subtitle: model.snapshot.systemVolume.deviceName, value: model.snapshot.systemVolume.value, muted: model.snapshot.systemVolume.muted, enabled: model.connected && model.snapshot.systemVolume.available,
                              set: { model.execute("system.volume", ["value": .number($0)]) }, mute: { model.execute("system.mute", ["value": .bool(!model.snapshot.systemVolume.muted)]) })
            }.padding(.top, 14)
        } label: { Label("声音设置", systemImage: "speaker.wave.2").font(.subheadline.weight(.medium)) }
        .padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func controlButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 22)).frame(width: 44, height: 48) }
            .accessibilityLabel(label).foregroundStyle(.primary)
    }
}

struct VolumeControl: View {
    let title: String, subtitle: String
    let value: Double, muted: Bool, enabled: Bool
    let set: (Double) -> Void, mute: () -> Void
    @State private var editing = false
    @State private var localValue: Double = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 3) { Text(title).font(.subheadline.weight(.semibold)); Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                Text("\(Int((editing ? localValue : value) * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack {
                Button(action: mute) { Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 36, height: 44) }.accessibilityLabel(muted ? "取消\(title)静音" : "\(title)静音")
                Slider(value: $localValue, in: 0...1) { changed in editing = changed; if !changed { set(localValue) } }.accessibilityLabel(title)
            }.disabled(!enabled)
        }.onChange(of: value, initial: true) { _, changed in if !editing { localValue = max(0, min(1, changed)) } }
    }
}

struct PlaybackListSection: View {
    @EnvironmentObject private var model: RemoteModel
    private var queue: QueueSnapshot { model.snapshot.queue }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.showsPlaylist {
                HStack {
                    Text(queue.source?.kind == "season" ? "正片选集" : queue.source?.kind == "creator" ? "UP 主投稿" : queue.source?.kind == "collection" ? "合集 / 系列" : queue.source?.kind == "favorites" ? "收藏夹" : "播放队列").font(.title3.bold())
                    Spacer()
                    Text("\(queue.index + 1) / \(queue.items.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if let message = queue.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                HStack {
                    Text(queue.active ? "连续播放中" : "连播已暂停").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if queue.active { Button("停止连播") { model.execute("queue.stop") }.disabled(!model.connected) }
                    else if queue.canResume { Button("继续播放") { model.execute("queue.resume") }.disabled(!model.ready) }
                }.font(.subheadline)
                LazyVStack(spacing: 0) {
                    ForEach(Array(queue.items.enumerated()), id: \.element.id) { index, item in
                        Button { model.execute("queue.select", ["bvid": .string(item.bvid)]) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text(String(index + 1)).font(.caption.monospacedDigit()).frame(width: 20)
                                CoverView(url: item.cover ?? (item.bvid == model.snapshot.player.bvid ? model.snapshot.player.cover : nil)).frame(width: 88, height: 50).clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title).font(.subheadline.weight(index == queue.index ? .semibold : .regular)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                                    if let reason = item.unavailableReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                                }
                                if index == queue.index { Image(systemName: "waveform").accessibilityLabel("当前播放") }
                            }.foregroundStyle(index == queue.index ? Color.biliPink : .primary).padding(.vertical, 14).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(!model.ready).accessibilityIdentifier("queueItem-\(item.bvid)")
                        Divider()
                    }
                }
                if queue.nextPage != nil { Text("后续视频会随播放自动载入").font(.caption).foregroundStyle(.secondary) }
            } else {
                HStack {
                    Text("相关视频").font(.title3.bold())
                    Spacer()
                    Button { Task { await model.loadRelated() } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                        .accessibilityLabel("刷新相关视频").disabled(!model.ready || model.relatedLoading)
                }
                Text("根据电脑当前视频推荐，点选即可播放").font(.caption).foregroundStyle(.secondary)
                if model.relatedLoading { ProgressView("正在读取相关视频…").font(.subheadline) }
                if let error = model.relatedError { Text(error).font(.footnote).foregroundStyle(.secondary) }
                if model.visibleRelatedVideos.isEmpty && !model.relatedLoading && model.relatedError == nil {
                    Text(model.ready ? "暂无相关视频，可以稍后刷新" : "连接电脑后显示相关视频").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
                }
                LazyVStack(spacing: 8) {
                    ForEach(model.visibleRelatedVideos) { video in
                        VideoRow(video: video).disabled(!model.ready).accessibilityIdentifier("relatedItem-\(video.bvid)")
                        Divider()
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("playbackList")
    }
}
