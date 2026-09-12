# 配对连接排查

## 已修复的两个问题

1. `Could not connect to the server.`：旧助手可能选择 Meta/Clash 等虚拟网卡地址。更新后会优先选择真实 Wi-Fi/以太网地址；刷新二维码重新扫描。
2. `cancelled`：旧助手生成五年期证书，Apple SSL 校验拒绝其有效期。已在 macOS 的 Security 框架复现 `-67901 / Certificate exceeds maximum temporal validity period`；相同扩展、密钥算法的一年期证书通过。助手已改用总有效期 365 天的证书，并自动迁移旧身份。Apple 的[证书要求](https://support.apple.com/en-us/103769)说明了相关限制。

2026-09-12 在用户实际安装的 Windows 助手中应用修复后，用户用手机原有 App 重新扫码，确认连接成功。此次连接修复不要求重新签名手机 App。

## 使用修复包

完整解压 `BiliRemote-Pairing-Fix.zip`，在 PowerShell 中运行：

```powershell
./apply-pairing-fix.ps1 -InstallationDirectory 'E:\BiliRemote'
```

路径应为实际安装目录，其中包含 `BiliRemote.exe`。脚本备份旧组件、停止该目录的助手、替换并核对两个 DLL 后重新启动。刷新电脑二维码，重新扫码。旧二维码的证书指纹不再匹配。

助手保留原加密身份备份及设备记录，不自动接受证书变化。证书到期更新后也需扫码确认新身份。程序备份位于安装目录的 `backup-pairing-*`，加密身份备份位于数据目录的 `identity.bin.previous-*`。

## iOS 0.1.1 的错误提示

- 证书不一致：确认是目标电脑，刷新其二维码重新扫描；如仍失败，检查代理是否拦截局域网连接。
- iOS 拒绝证书：更新电脑助手，确认两端日期时间。提示会保留 Apple 的具体校验错误。
- 无法连接：确认同一路由器、助手显示真实局域网地址、iPhone 允许 App 使用本地网络。检查 Windows 防火墙与访客 Wi-Fi 隔离设置。
- 二维码过期：电脑端刷新后两分钟内扫描；每个二维码只可成功配对一次。

请勿通过关闭证书校验或改用明文 HTTP 处理连接问题。
