import SwiftUI
import AVFoundation
import AppIntents

struct DevicesView: View {
    @EnvironmentObject private var model: RemoteModel
    @State private var pairingText = ""
    @State private var scanner = false
    @State private var tabs: [BrowserTab] = []
    @State private var loadingTabs = false
    @ObservedObject private var watch = PhoneWatchBridge.shared
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) { Image(systemName: "desktopcomputer").font(.largeTitle).foregroundStyle(Color.biliPink); VStack(alignment: .leading, spacing: 5) { Text(model.device?.computerName ?? "连接你的电脑").font(.headline); Text(model.status == .connected ? "局域网已连接" : model.status == .connecting ? "正在连接…" : "尚未连接").font(.subheadline).foregroundStyle(.secondary) }; Spacer(); if model.status == .connecting { ProgressView() } }
                if let device = model.device { Text("\(device.host):\(device.port)").font(.caption.monospaced()).foregroundStyle(.secondary); Button("重新连接") { model.background(); model.connect() }; Button("忘记这台电脑", role: .destructive) { model.forget() } }
                if let hint = model.connectionHint { Text(hint).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("配对电脑") {
                Button { scanner = true } label: { Label("扫描电脑二维码", systemImage: "qrcode.viewfinder") }.disabled(model.pairing)
                TextField("或粘贴电脑助手的配对信息", text: $pairingText, axis: .vertical).lineLimit(2...4).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button { Task { await model.pair(pairingText) } } label: { HStack { Text("连接并保存"); if model.pairing { Spacer(); ProgressView() } } }.disabled(pairingText.isEmpty || model.pairing)
            }
            Section { Text("1. 手机与电脑连接同一路由器。\n2. 运行 Windows 助手，并允许专用网络连接。\n3. 在 Chrome 加载哔哩遥控扩展。\n4. 扫描助手中的配对二维码。").font(.footnote).foregroundStyle(.secondary) } header: { Text("首次使用") } footer: { Text("二维码两分钟有效。你的哔哩哔哩登录状态保留在电脑浏览器内。") }
            if model.connected {
                Section("选择播放标签页") {
                    if !model.snapshot.browserConnected { Text("请先打开 Chrome，并在扩展中重新连接助手。").font(.footnote) }
                    ForEach(tabs) { tab in Button { model.execute("tabs.select", ["tabId": .number(Double(tab.id))]); Task { try? await Task.sleep(for: .milliseconds(400)); await refreshTabs() } } label: { HStack { Text(tab.title).lineLimit(2); Spacer(); if tab.selected { Image(systemName: "checkmark.circle.fill") } } } }
                    Button { Task { await refreshTabs() } } label: { HStack { Text("刷新标签页"); if loadingTabs { Spacer(); ProgressView() } } }.disabled(!model.snapshot.browserConnected || loadingTabs)
                    Text("选定后固定控制此标签页；没有合适的标签页时，点播视频会自动创建。").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Siri 与快捷指令") {
                SiriTipView(intent: PlaybackIntent(action: .play))
                Text("试着说：嘿 Siri，用哔哩遥控暂停播放。也支持继续播放、上一条、下一条、前后十秒和音量。").font(.footnote).foregroundStyle(.secondary)
                Text("先完成电脑配对并允许局域网访问，再在快捷指令 App 中查看哔哩遥控的操作。").font(.caption).foregroundStyle(.secondary)
            }
            Section("Apple Watch") {
                Label(watch.status, systemImage: "applewatch")
                Text("在 iPhone 的 Watch App 中安装哔哩遥控，即可在手表查看播放状态、播放或暂停、切换视频、前后十秒和调节音量。需要 iPhone 能连接同一局域网内的电脑。").font(.footnote).foregroundStyle(.secondary)
            }
            Section { Text("Bili Remote \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · 自用版").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("设备")
            .sheet(isPresented: $scanner) { NavigationStack { QRScanner { text in scanner = false; Task { await model.pair(text) } }.ignoresSafeArea(edges: .bottom).navigationTitle("扫描电脑二维码").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { scanner = false } } } } }
            .onChange(of: model.snapshot.browserConnected, initial: true) { _, ready in if ready && model.connected { Task { await refreshTabs() } } }
    }
    private func refreshTabs() async { guard !loadingTabs else { return }; loadingTabs = true; defer { loadingTabs = false }; do { tabs = try await model.transport.request("tabs.list") } catch { model.error = error.localizedDescription } }
}
struct QRScanner: UIViewControllerRepresentable {
    let scanned: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController { let controller = ScannerController(); controller.scanned = scanned; return controller }
    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}
}
final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var scanned: ((String) -> Void)?
    private let capture = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.biliremote.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var completed = false
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            if granted { self.queue.async { self.setup() } }
            else { DispatchQueue.main.async { self.showMessage("请在系统设置中允许相机访问，\n或返回后粘贴配对信息。") } }
        }
    }
    private func setup() {
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), capture.canAddInput(input) else { DispatchQueue.main.async { self.showMessage("相机不可用，请使用粘贴配对信息。") }; return }
        capture.beginConfiguration(); capture.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard capture.canAddOutput(output) else { capture.commitConfiguration(); return }
        capture.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]; capture.commitConfiguration()
        DispatchQueue.main.async { let layer = AVCaptureVideoPreviewLayer(session: self.capture); layer.videoGravity = .resizeAspectFill; layer.frame = self.view.bounds; self.view.layer.addSublayer(layer); self.preview = layer }
        capture.startRunning()
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); queue.async { self.capture.stopRunning() } }
    private func showMessage(_ message: String) { let label = UILabel(); label.text = message; label.numberOfLines = 0; label.textAlignment = .center; label.textColor = .white; label.frame = view.bounds.insetBy(dx: 24, dy: 100); label.autoresizingMask = [.flexibleWidth, .flexibleHeight]; view.addSubview(label) }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !completed, let code = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let value = code.stringValue, value.hasPrefix("biliremote://pair") else { return }
        completed = true; queue.async { self.capture.stopRunning() }; scanned?(value)
    }
}
