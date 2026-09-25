# 哔哩遥控 · Bili Remote

原生 iOS 遥控器，用手机搜索和选片，让 Windows Chrome 中的哔哩哔哩网页播放。

支持 iOS 17+、可选的 watchOS 10+ 配套 App、Windows 10/11 x64 和当前稳定版 Chrome。手机与电脑需在同一局域网；电脑可以连接网线。

## 安装

1. 安装 `BiliRemote-Setup-0.4.0.exe`，启动电脑助手。也可完整解压 `BiliRemote-Windows.zip`，用 PowerShell 运行其中的 `install.ps1` 注册当前用户的浏览器通信组件，然后启动 `BiliRemote.exe`。便携目录注册后不要移动。
2. 在 Chrome 打开 `chrome://extensions`，开启开发者模式，点击“加载已解压的扩展程序”，选择助手安装目录内的 `extension` 文件夹。默认安装目录为 `%LOCALAPPDATA%\Programs\BiliRemote`。扩展固定 ID 为 `penfpdlcbljgooeeabnkphfggjhbfnnj`。
3. 在助手中点击“允许局域网连接”，接受 Windows 的管理员提示。这条规则只允许专用网络中同一子网连接该程序；网络设为公用时不会生效。
4. 给 `BiliRemote-unsigned.ipa` 使用你自己的方式签名并安装到 iPhone。它是真机 arm64 应用，未包含个人证书或描述文件。
5. 在 App 的“设备”页扫描助手中的二维码，允许相机和局域网权限。二维码两分钟有效且只能用一次；过期后在电脑端刷新。
6. 保持 Chrome 和助手运行，在电脑浏览器正常登录哔哩哔哩。首次播放若受到浏览器自动播放策略限制，在电脑视频区域手动点一次播放后重试。

## 使用

- 在“发现”搜索视频或 UP 主；主页包含简介、认证、粉丝、关注、投稿和获赞，支持投稿内搜索、最新 / 最早 / 最多播放排序、合集和系列。
- “收藏”显示电脑 Chrome 当前登录账号的收藏夹，可搜索收藏夹、点播或播放整个收藏夹；连播会自动加载后续页面。暂只显示视频类收藏，失效视频会标记。
- 在播放页打开“查看评论 / 发表评论”，支持热门 / 最新排序、翻页、展开楼中楼及回复。点击发送后使用电脑账号发表；发送失败保留草稿，结果不明确时应先刷新核对。
- Siri 可说“用哔哩遥控暂停播放”“用哔哩遥控播放下一个视频”，也支持继续播放、上一条、前后十秒和音量；可以在快捷指令 App 中选择这些操作。首次使用先在手机完成配对和局域网授权。
- Apple Watch 配套 App 提供播放状态、暂停 / 继续、前后十秒、上一条 / 下一条和音量。它通过 iPhone 连接电脑，断连指令不会排队补发；手机 App 不能被强制退出，且需能访问电脑所在的局域网。
- “全部播放”在电脑维护队列，手机锁屏或离开 App 后，电脑仍可继续播放。
- “播放”页支持暂停、上一项/下一项、前后 10 秒、拖动进度、输入准确时间、0.5～2 倍速、弹幕与全屏。
- 0.4.0 在“播放”页加入“清晰度”：显示当前档位、画面尺寸和网页实际提供的选项（含自动），点击后通过电脑播放器切换。高码率 / 4K 等取决于视频和账号权限；登录或会员提示需要在电脑处理。需同步更新助手、扩展与 IPA，并重新加载扩展、刷新 B 站页面。
- 播放列表位于播放控制下方，整页向下滚动可见；合集/全部投稿显示队列，单独视频显示相关推荐。0.2.0 不再提供独立的队列标签页。[升级说明](docs/RELEASE-0.2.0.md)。
- 网页音量和电脑音量分开控制；电脑音量作用于 Windows 当前默认输出设备。
- “设备”页可选择已有的播放标签页。选择后控制目标固定，不会随电脑当前焦点切换。
- 助手重启后会恢复上次队列与进度，点击“继续播放”恢复，不会自行出声。
- 电脑助手关闭窗口后留在托盘。要彻底停止，请选择“退出助手”。在助手中解绑设备会立即断开该手机。

## 构建

需要 .NET 10 SDK、Node.js 24；编译 iOS 需要 macOS、Xcode 和 XcodeGen。

```powershell
# Windows：测试并生成独立运行的助手、扩展 ZIP 和安装包
./scripts/build-windows.ps1
```

生成 `.exe` 安装程序需要 Inno Setup 6；缺少时仍会生成完整便携安装 ZIP。项目不依赖本机手动设置的全局 Node/.NET 开发服务。若系统只有旧版 .NET SDK，可使用 `./scripts/build-windows.ps1 -Dotnet ./.tools/dotnet/dotnet.exe`（需要该目录已有 .NET 10 SDK）。

```sh
# Mac：生成工程，在 Xcode 中运行或按 workflow 构建
cd ios
xcodegen generate
open BiliRemote.xcodeproj
```

GitHub Actions 工作流分别构建 Windows/Chrome 和 iOS。下载 `BiliRemote-iOS-unsigned` 和 `BiliRemote-Windows-Installer` 即可；安装程序内含扩展。`BiliRemote-Chrome` 提供独立扩展，`BiliRemote-Windows-Portable` 是可选便携包。无需向 GitHub 上传签名证书。`scripts/verify-ipa.py` 会检查 IPA 的真机平台、arm64 可执行文件和权限说明。Actions 产物空间不足时，可手动触发工作流并选择 `delivery=draft-release`；它会运行 iOS / Watch 构建及测试，将 IPA、SHA-256 和界面截图保存到当前仓库的草稿 Release，不会自动公开发布。

更新这批功能需要同时更新电脑助手、Chrome 扩展与 iPhone App。扩展新增哔哩哔哩 API 域名访问及 cookies 权限，用于读取收藏和在浏览器内取得评论 CSRF 值；不会把浏览器 Cookie 传给手机或电脑助手。更新后在 `chrome://extensions` 重新加载扩展并检查权限提示。

Apple Watch App 会嵌入 iPhone IPA；重签名时必须同时签名 Watch 子应用，并保持 `WKCompanionAppBundleIdentifier` 与实际 iPhone Bundle ID 一致。在 iPhone 的 Watch App 中安装配套应用。构建及真机验收状态见[新增功能验证记录](docs/COMMUNITY-AND-WATCH.md)。

## 排查

2026-09-12 配对证书修正：旧助手的五年期证书会被 iOS 拒绝，旧 App 仅显示 `cancelled`。更新助手后会备份旧身份并生成一年期证书，刷新二维码重新扫码即可；现有 iOS App 可继续使用。iOS 0.1.1 另增加了证书与网络错误的中文诊断。详情见[配对排查](docs/PAIRING-TROUBLESHOOTING.md)。

2026-09-12 局域网修正：自动配对地址优先选择连接路由器的 Wi-Fi/以太网，排除 Meta/Clash、Tailscale 和虚拟机网卡。若旧版助手显示 `198.18.*` 等虚拟网卡地址，请更新电脑助手后刷新二维码并重新配对，手机 IPA 无需重新签名。

| 现象 | 处理 |
|---|---|
| 手机无法连接 | 检查同一路由器、助手中的 IP、iOS 局域网权限、Windows 专用网络和防火墙；访客 Wi-Fi/AP 隔离可能阻断设备互访。 |
| 助手显示扩展断开 | 运行安装程序或便携注册脚本；启动 Chrome；在扩展弹窗点击重新连接。 |
| IP 地址变化 | 退出再启动助手，使用新二维码重新配对。多网卡情况下可通过 `BILIREMOTE_BIND` 指定本机 IPv4 地址。 |
| 视频未自动播放 | 在电脑播放器手动点击一次播放，再从手机重试。 |
| 搜索或目录读取失败 | 查看电脑中的目录标签页是否有登录/安全验证或网络错误；完成后重试。网站改版需要更新扩展适配层。 |
| 电脑休眠或 Chrome 关闭 | 遥控与连播需要电脑保持运行；恢复后重连并选择继续播放。 |
| 重签名后配对丢失 | 更换签名团队/应用标识可能改变 Keychain 访问范围，重新扫码即可。 |

## 开发与验证

- `desktop/`：.NET 队列核心、WPF 助手、Native Messaging 桥。
- `extension/`：TypeScript 浏览器后台、目录和播放器适配器。
- `ios/`：SwiftUI App、TLS 指纹验证、Keychain、扫码和 XCTest。
- [协议说明](protocol/README.md) 与 [验收记录](docs/VALIDATION.md)。

首版不提供公网控制、直播、投屏或 iOS 锁屏控制面板。仅执行网页播放及音量控制，不提供任意远程脚本执行。
