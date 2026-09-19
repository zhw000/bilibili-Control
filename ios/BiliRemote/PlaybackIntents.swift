import AppIntents

enum SiriPlaybackAction: String, AppEnum {
    case play, pause, next, previous, forward, backward, volumeUp, volumeDown
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "播放操作"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .play: "继续播放", .pause: "暂停播放", .next: "播放下一个视频", .previous: "播放上一个视频",
        .forward: "前进十秒", .backward: "后退十秒", .volumeUp: "增大音量", .volumeDown: "减小音量"
    ]
}

struct PlaybackIntent: AppIntent {
    static var title: LocalizedStringResource = "控制电脑上的哔哩哔哩"
    static var description = IntentDescription("使用已配对的电脑播放、暂停、切换视频、跳转进度或调整音量。iPhone 与电脑需要在同一局域网。")
    static var openAppWhenRun = false
    @Parameter(title: "播放操作", default: .play) var action: SiriPlaybackAction
    static var parameterSummary: some ParameterSummary { Summary("在电脑上\(\.$action)") }
    init() {}
    init(action: SiriPlaybackAction) { self.action = action }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let command = RemoteAction(rawValue: action.rawValue) else { throw RemoteFailure(code: "invalid_action", message: "播放操作无效。") }
        let snapshot = try await RemoteCommandClient.perform(command)
        PhoneWatchBridge.shared.publish(snapshot, connected: true, force: true)
        return .result(dialog: "已执行：\(command.title)")
    }
}

struct PlaybackShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlaybackIntent(), phrases: ["用\(.applicationName)\(\.$action)", "用\(.applicationName)播放视频"], shortTitle: "遥控播放", systemImageName: "play.circle")
    }
}
