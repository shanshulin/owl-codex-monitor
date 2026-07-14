# Owl Codex Monitor

用于查看 Owl AI 订阅用量的轻量级 macOS 菜单栏应用。

## 已修复问题

- 修复登录会话轮换时，旧刷新请求可能将新登录状态错误显示为“登录已过期”的问题。
- 修复昨日结余已消费后，未计入“今日（含结余）”已用量与剩余额度的问题。
- 刷新令牌失效后，自动使用本机 Keychain 中的登录凭据后台重新登录，无需重复输入账号密码。

## 直接安装

下载 [Owl-Codex-Monitor-macOS-universal.zip](releases/Owl-Codex-Monitor-macOS-universal.zip)，解压后将 `Owl Codex Monitor.app` 拖入“应用程序”文件夹并打开。

首次打开时，如 macOS 提示无法确认开发者，请按住 Control 点按应用，选择“打开”后确认即可。

## 兼容性

- 支持 Apple Silicon（`arm64`）和 Intel（`x86_64`）Mac。
- 需要 macOS 13 或更高版本。
- 仓库和安装包均不包含 Keychain 数据、账号密码、刷新令牌或本机开机自启设置。

## 功能

- 左侧圆环显示日额度用量。
- 中间圆环显示周额度用量。
- 右侧圆环显示月额度用量。
- 网站取消日限后，应用会隐藏日额度与昨日结余，只显示周、月两个圆环。
- 前一天仍有效的结余会自动计入当天总额度。
- 结余有效期间，菜单会显示对应明细。
- 点按圆环可查看精确用量和剩余额度，并可刷新、登录或退出登录。
- 按住 Command 拖动菜单栏图标，可在避开刘海的状态栏区域调整位置。

## 从源码构建

```bash
swift run OwlCodexMonitor --self-test
./scripts/build-app.sh
open "dist/Owl Codex Monitor.app"
```

## 数据安全

登录信息只会发送至 `https://api.owlai.tech`。邮箱、登录密码和刷新令牌仅存储在本机 macOS Keychain 中；退出登录会一并清除。

菜单提供刷新、登录、退出登录和退出应用操作。
