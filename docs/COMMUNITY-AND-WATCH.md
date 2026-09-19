# 收藏、评论、Siri 与 Apple Watch

## 本次实现

- 收藏：独立标签页、账号名、收藏夹列表、夹内搜索、点播和整夹连播；队列保存收藏夹与搜索条件，自动翻页，跳过没有视频的目录页。
- 评论：热门 / 最新、分页、楼中楼、用户主页入口、发评论与回复；草稿在失败时保留，发送期间禁用重复点击，结果不明确时提示先核对评论。
- UP 主：头像、简介、认证、等级、粉丝 / 关注 / 投稿 / 获赞，投稿内搜索与三种排序，合集和系列。
- 封面：修复 data URI 占位图遮盖真实地址、picture/srcset 读取、重复卡片覆盖封面和过早返回的问题；加入缺失信息与图片下载自动重试、原图地址标准化、缩略图缓存。播放队列也显示封面。
- Siri：一个可选择操作的 App Intent，支持播放、暂停、上一条 / 下一条、前后十秒和音量。例：“嘿 Siri，用哔哩遥控暂停播放”。
- Apple Watch：watchOS 10+ 配套界面，同步视频名 / 进度 / 暂停状态，提供播放控制。通过 iPhone 短连接访问电脑，不复制配对密钥到手表，不积压离线指令。

## 更新和签名

需要一起更新 Windows 助手、Chrome 扩展、iPhone App。Chrome 扩展新增 `api.bilibili.com` 主机权限及 `cookies` 权限；只在浏览器内用 `bili_jct` 完成评论 CSRF 校验。手机不会收到浏览器 Cookie。

Mac 上运行 `cd ios && xcodegen generate`，构建 `BiliRemote` scheme；生成的工程会同时构建并嵌入 `BiliRemoteWatch.app`。iPhone 与 Watch 子应用需要各自有效签名，Watch 子应用的 `WKCompanionAppBundleIdentifier` 必须匹配签名后的手机 Bundle ID。自动构建新增 Watch 模拟器构建步骤，IPA 校验脚本会检查手表包、平台、版本和配套关系。

在手机上首次完成局域网授权和电脑配对，再测试 Siri；在 iPhone 的 Watch App 中安装配套 App。手表需要能联系 iPhone，iPhone 需要能访问电脑所在的局域网。强制退出 iPhone App 后需要重新打开。

## 2026-09-19 本机验证

- Chrome TypeScript 类型检查：通过。
- 扩展测试：34 / 34 通过，包含懒加载封面、延迟加载、永久缺图、收藏分页、评论长 ID、CSRF、重复发送及异常路径。
- 扩展打包：通过，输出 `extension/dist/`。
- .NET 单元测试：36 / 36 通过。
- Windows 助手 Release 构建：通过，零警告、零错误。
- 本机 TLS / WebSocket / Native Messaging 集成检查：23 / 23 通过，包含评论去重、收藏自动翻页和读取目录不影响播放；使用模拟手机和浏览器。
- 对哔哩哔哩官方服务的只读验证：`/x/web-interface/card` 与 `/x/v2/reply` 返回 `code=0`。没有使用真实账号发表评论。
- 新增 iOS 测试覆盖封面 URL、评论 ID、Siri / Watch 指令边界、恢复队列与手表状态序列化；UI 测试加入收藏入口。

本机为 Windows，没有 Xcode：iOS / watchOS 编译、XCTest、Siri 识别和 Apple Watch 真机控制尚未执行。也尚未验证真实登录账号的收藏读取、评论发送与最新 UP 主网页搜索 / 排序。以上项目不能视为已验收。

## 真机验收

1. 更新并重新加载扩展，登录电脑 B 站；确认手机能显示自己的收藏夹、私有收藏夹和多页视频，搜索结果点播 / 连播正常。
2. 打开一个有评论的视频，切换热门 / 最新，翻页、展开回复。仅在确认正文后发送一条真实评论，核对作者、目标视频及显示结果；网络中断后确认不会自动重发。
3. 连续点开不同视频，首次进入播放列表应自动显示封面；慢网下标题先出现时，封面应随后补齐，无须手动刷新。检查图片失败后自动重试及切换视频不会串图。
4. 打开 UP 主主页，核对资料、搜索、最新 / 最早 / 最多播放及合集翻页。
5. 前台和锁屏分别通过 Siri 暂停、恢复、前后十秒、切换队列并调整音量，检查未配对 / 电脑离线时的错误提示。
6. 手表检查状态、上一条 / 下一条边界、音量、手机后台时的控制；断开手机连接后点击操作，再恢复连接，确认没有延迟执行旧命令。

## 接入依据

- [Apple App Intents](https://developer.apple.com/documentation/appintents/appintent)
- [Apple WatchConnectivity 数据传输](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)
- [XcodeGen 工程配置](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)

哔哩哔哩网站接口和 DOM 可能变化；适配失败会显示登录、验证、关闭评论或接口错误，不能保证网站后续兼容。
