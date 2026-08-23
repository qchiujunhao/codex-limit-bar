# Codex Limit Bar

An unofficial native macOS menu bar app for checking Codex 5-hour and weekly usage limits at a glance.

Codex Limit Bar 在菜单栏显示真实剩余额度。点击状态项后，可以查看各额度窗口、重置时间、当前套餐和可用重置次数。

The interface supports English and Simplified Chinese. English is the default; the language menu in the popover switches the entire interface immediately and remembers your choice.

## 显示规则

菜单栏分别显示 Codex 的 **5 小时额度**与**每周额度**：

- 两个窗口都返回时：`5h 80%  周 43%`
- 接口暂时没有返回 5 小时窗口时：只显示 `周 43%`
- 5 小时窗口恢复后会在下一次刷新时自动出现

默认英文界面对应显示为 `5h 80%  Wk 43%`；缺少 5 小时窗口时只显示 `Wk 43%`。

## 功能

- 在 macOS 菜单栏显示 Codex 剩余额度及颜色进度条
- 分别显示 5 小时额度和每周额度
- 5 小时额度未返回时自动隐藏该项
- English / 简体中文即时切换，默认英文并记住选择
- 查看各额度窗口、重置时间、套餐及可用重置次数
- 每 60 秒自动刷新，并支持手动刷新
- 连接中断或超时后自动重试
- 数据过期时保留上次结果并显示 `!`
- 不读取、复制或保存 ChatGPT 登录令牌
- 原生 AppKit 应用，支持 Apple Silicon 与 Intel Mac

## 系统要求

- macOS 13 或更高版本
- 已安装并登录 ChatGPT/Codex 桌面 App，或已安装并登录 Codex CLI

## 下载与安装

从仓库的 [Releases](../../releases) 下载 `Codex-Limit-Bar.zip`，解压后运行 `Codex Limit Bar.app`。

当前构建使用 ad-hoc 签名且未公证。如果 macOS 首次启动时拦截，可在 Finder 中右键应用并选择“打开”。

应用没有 Dock 图标。点击菜单栏额度条，再点 `Quit` / `退出` 即可关闭。语言可在同一面板底部切换。

## 数据来源与隐私

应用通过本机 Codex App Server 的官方 `account/rateLimits/read` 方法读取额度信息；`usedPercent`、额度窗口长度与重置时间都来自该接口。认证由本机 ChatGPT/Codex 登录状态处理。

应用不会自行读取、复制或保存登录令牌，也不会把额度数据发送到第三方服务。参见 [OpenAI Codex App Server 文档](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt)。

语言选择仅保存在本机 `UserDefaults` 中。

## 从源码构建

需要安装 Xcode 或 Xcode Command Line Tools。

```bash
./scripts/test.sh
./scripts/build.sh
```

构建结果：

- `dist/Codex Limit Bar.app`
- `dist/Codex-Limit-Bar.zip`

构建脚本会生成支持 `arm64` 与 `x86_64` 的 Universal Binary，最低部署目标为 macOS 13。

## macOS 菜单栏限制

macOS 将左侧应用菜单与右侧状态区分开管理。独立应用只能创建右侧状态项，不能固定插入当前 App 的 `Help` 菜单后面。可按住 Command 拖动额度条，在右侧状态项之间调整顺序。

## 故障排除

- 显示 `?%`：尚未成功读取数据。确认 ChatGPT/Codex 已登录，然后打开面板点“刷新”。
- 显示 `!`：当前显示的是上次成功读取的旧值，应用正在自动重连。
- 找不到状态项：菜单栏空间不足时 macOS 可能临时隐藏部分状态项。
- API Key 登录：ChatGPT 套餐额度需要使用 ChatGPT 登录模式，API Key 模式没有对应的套餐额度窗口。

## 声明

This is an unofficial community project and is not affiliated with or endorsed by OpenAI. Codex, ChatGPT, and OpenAI are trademarks of OpenAI.
