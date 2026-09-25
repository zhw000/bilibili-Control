import SwiftUI

struct QualityView: View {
    @EnvironmentObject private var model: RemoteModel
    @Environment(\.dismiss) private var dismiss
    @State private var pending: String?
    @State private var failure: String?
    private var player: PlayerState { model.snapshot.player }
    private var videoKey: String { "\(player.bvid):\(player.part)" }

    var body: some View {
        NavigationStack {
            List {
                if let quality = player.quality {
                    Section {
                        LabeledContent("当前档位", value: quality.displayName)
                        if let width = quality.width, let height = quality.height, width > 0, height > 0 {
                            LabeledContent("当前画面", value: "\(width) × \(height)")
                        }
                    }
                    Section {
                        if quality.options.isEmpty {
                            Text("网页暂未提供清晰度选项，请等视频加载完成，或刷新电脑上的视频页面。").foregroundStyle(.secondary)
                        }
                        ForEach(quality.options) { option in
                            Button { Task { await select(option.id) } } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(option.label).foregroundStyle(.primary)
                                        if let badge = option.badge { Text(badge).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer(minLength: 8)
                                    if pending == option.id { ProgressView().accessibilityLabel("正在切换") }
                                    else if quality.currentId == option.id { Image(systemName: "checkmark").accessibilityLabel("当前清晰度") }
                                }.padding(.vertical, 4).contentShape(Rectangle())
                            }.disabled(!model.ready || pending != nil || option.disabled).accessibilityIdentifier("quality-\(option.id)")
                        }
                    } footer: {
                        Text("选项来自电脑播放器。部分清晰度需要登录或大会员，切换时可能短暂缓冲。")
                    }
                } else {
                    Text("请更新电脑助手和 Chrome 扩展，重新加载扩展并刷新 B 站页面，以启用清晰度切换。").foregroundStyle(.secondary)
                }
                if !model.ready { Text("电脑或浏览器已断开，连接后可切换清晰度。").foregroundStyle(.secondary) }
                if let failure { Text(failure).foregroundStyle(.red).accessibilityIdentifier("qualityError") }
            }
            .navigationTitle("视频清晰度").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onChange(of: videoKey) { _, _ in failure = nil }
        }
    }

    @MainActor private func select(_ id: String) async {
        guard pending == nil, model.ready, id != player.quality?.currentId else { return }
        let key = videoKey
        pending = id; failure = nil
        defer { pending = nil }
        do { try await model.setQuality(id, bvid: player.bvid, part: player.part) }
        catch { if videoKey == key { failure = error.localizedDescription } }
    }
}
