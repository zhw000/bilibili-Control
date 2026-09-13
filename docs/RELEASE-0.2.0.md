# 0.2.0 升级与使用

## 手机更新

使用 `BiliRemote-0.2.0-unsigned.ipa`，按原来的方式签名后覆盖安装。设备页底部应显示 `Bili Remote 0.2.0`。保持原来的签名团队和应用标识；如果配对信息未保留，在电脑助手刷新二维码重新扫描即可。

## 电脑更新

安装 `BiliRemote-Setup-0.2.0.exe`，选择原来的安装目录；或者解压 `BiliRemote-Desktop-Update-0.2.0.zip`，运行其中的脚本：

```powershell
./apply-player-update.ps1 -InstallationDirectory 'E:\BiliRemote' -ExtensionDirectory 'C:\Users\asus\Documents\ChatGPT\bilibili-Control\artifacts\delivery\final\Chrome扩展'
```

两个路径都应换成实际路径。更新脚本保留配对数据并备份旧组件。在 Chrome 的 `chrome://extensions` 中找到“哔哩遥控”，点击重新加载，并刷新已打开的哔哩哔哩播放网页。扩展卡片应显示 `0.2.0`。

本次在当前电脑已完成助手与扩展文件更新，用户截图确认 Chrome 已重载为 0.2.0。

## 使用变化

- 封面采用 16:9，并限定在屏幕宽度内；长标题与播放控制不再撑出屏幕。
- 底部只保留“发现、播放、设备”，播放列表移到“播放”页面下方，整页纵向滚动。
- 播放 UP 主全部投稿、合集或系列时显示队列，点选某条会保留原队列及后续分页。
- 单独播放视频时显示当前网页的相关视频；点选推荐即可播放。“下一项”选择第一条推荐，不自动开启推荐连播。
- “声音设置”可展开视频音量与电脑音量，静音仍分别控制。
- 读取相关推荐不会导航或刷新电脑的播放页；换片后旧请求不会覆盖新视频的推荐列表。

## 扩展重载后的提示

`Uncaught Error: Extension context invalidated.` 表示仍打开的旧网页脚本使用了重载前的扩展上下文。刷新那张哔哩哔哩网页即可加载新脚本；管理页中的旧错误记录可清除，无需重新配对。

## 验证

本地核心测试 35 项、扩展测试 17 项通过；Windows HTTPS/WSS 与 Native Messaging 管道集成检查 18 项通过，包含相关视频查询不改变播放、队列点选保留来源及分页。网页推荐栏结构已在当前 Chrome 实际页面检查。

iOS 测试覆盖真实证书 HTTPS/WSS、普通屏幕与小屏、横屏、大字体、加载大尺寸封面后的边界、一个滚动区域内的队列和相关推荐。构建结果与二进制哈希见交付目录的 `build-info.json`、`SHA256SUMS.txt`。界面截图使用明确的测试视频数据，真机需安装新 IPA 后验证。
