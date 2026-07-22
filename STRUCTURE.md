# 次元虾 — 当前源码结构

> 版本：v2.5.0+143（当前显示序列起点 v2.5） | 协议：MIT | 更新日期：2026-07-22

本文描述当前工作区的真实结构。应用已经去掉 OpenClaw 首次启动、Gateway、AI 提供商、消息平台、节点能力、cpolar、SSH、本地模型、备份中心、设置/更新等主界面功能；主界面只保留 CLI 工具与终端。

## 1. 项目总览

次元虾现在是 Android 上的 CLI/runtime 容器：Flutter 提供安装向导、CLI 工具入口、终端入口和本地 API 代理管理；Kotlin 原生层负责 PRoot、Ubuntu RootFS、终端 Activity、Codex 浏览器侧栏、本地 api2py 代理前台服务和基础文件/权限桥接。

核心运行时仍是 PRoot Ubuntu RootFS。默认 Node.js 策略为：

- `arm64` / `x86_64`：Node.js `24.15.0`。
- `armeabi-v7a` / `armhf`：Node.js `22.22.3`。

新预构建 RootFS 不再安装或要求 OpenClaw，也不再预装 OpenClaw QQ/Weixin 插件。RootFS 资产仍沿用历史文件名 `openclaw-rootfs-noble-arm64.tar.gz` 以保持 Flutter 资产路径兼容，但 manifest 格式已经切到 `ciyuanxia-prebuilt-rootfs-manifest`。

## 2. 技术栈

| 层 | 技术 | 当前用途 |
|---|---|---|
| App 框架 | Flutter / Material 3 | 安装向导、Dashboard、CLI 工具、终端 fallback UI |
| 状态管理 | Provider | `LocaleProvider`、`SetupProvider` |
| WebView | webview_flutter | 本地 api2py 管理页、Flutter fallback 浏览器自动化 |
| 网络 | dio + http | 运行时下载、代理健康检查、资源获取 |
| 本地存储 | shared_preferences + path_provider | 语言、setup 状态、CLI/API 配置 |
| Android 原生 | Kotlin | PRoot、终端 Activity、Codex 原生浏览器、本地 API 代理服务 |
| 终端 | Termux terminal-view | 原生终端、Codex 双页终端/浏览器 |
| RootFS | Ubuntu 24.04 noble + PRoot | Node.js、CLI 工具、本地 api2py 代理 |

## 3. 目录结构

```text
openclaw-termux-zh/
├── flutter_app/
│   ├── android/app/src/main/
│   │   ├── AndroidManifest.xml
│   │   ├── kotlin/com/nxg/openclawproot/
│   │   │   ├── MainActivity.kt
│   │   │   ├── BootstrapManager.kt
│   │   │   ├── ProcessManager.kt
│   │   │   ├── TerminalSessionService.kt
│   │   │   ├── LocalApiProxyForegroundService.kt
│   │   │   ├── NativeTerminalActivity.kt
│   │   │   ├── NativeTerminalPagerActivity.kt
│   │   │   ├── NativeTerminalSessionView.kt
│   │   │   └── NativeCodexBrowserView.kt
│   │   └── res/drawable-nodpi/lucide_*.png
│   ├── assets/
│   │   ├── api2py/
│   │   ├── bootstrap/openclaw-rootfs-noble-arm64.tar.gz
│   │   └── open_source/*.md
│   ├── lib/
│   │   ├── app.dart
│   │   ├── constants.dart
│   │   ├── providers/
│   │   ├── screens/dashboard_screen.dart
│   │   ├── screens/cli_tools_screen.dart
│   │   ├── screens/terminal_screen.dart
│   │   ├── services/cli_api_config_service.dart
│   │   ├── services/local_api_proxy_service.dart
│   │   ├── services/native_bridge.dart
│   │   └── widgets/terminal_browser_panel.dart
│   └── pubspec.yaml
├── lib/test.js
├── scripts/
└── .github/workflows/flutter-build.yml
```

## 4. Flutter 应用层

`flutter_app/lib/app.dart` 只注入语言和 setup 状态。`DashboardScreen` 是主入口页，只导航到：

- `CliToolsScreen`：安装/启动 Codex、Claude、Gemini 等 CLI，管理 CLI API 配置和本地 api2py 中转代理。
- `TerminalScreen`：直接进入 RootFS 终端。

仍需保留的服务边界：

- `CliApiConfigService`：生成 CLI 配置、Codex 浏览器 MCP/脚本桥接、本地代理配置。
- `LocalApiProxyService`：管理 `127.0.0.1:9999` api2py 代理和管理页。
- `BrowserAutomationService` / `NativeBrowserAutomationDelegate`：Codex 浏览器自动化桥接。
- `TerminalService`：生成终端启动配置并调用 native terminal Activity。
- `BootstrapService`：RootFS、Node.js、bionic bypass、api2py 资产安装。

已删除的 Flutter 功能面不要恢复，除非用户明确要求：设置/更新、包管理、SSH、cpolar、本地模型、节点能力、备份中心、OpenClaw provider/gateway/message/onboarding/log/config UI。

## 5. Android 原生层

`MainActivity.kt` 提供 MethodChannel：setup、RootFS 文件读写、终端 Activity、Codex 原生浏览器动作、本地 API 代理、通知、存储权限和电池优化请求。

当前保留的前台服务：

- `SetupService`：安装过程通知。
- `TerminalSessionService`：终端会话保活。
- `LocalApiProxyForegroundService`：api2py 本地代理保活。

当前已删除的 native 服务：OpenClaw Gateway、Node foreground service、cpolar、本地模型、SSH、屏幕录制、悬浮文件管理。

`ProcessManager.kt` 仍提供两类 PRoot 命令：

- install mode：短命令、bootstrap、安装和修复。
- login mode：长驻 RootFS 进程，目前用于本地 api2py 代理。

## 6. 资源与许可

`flutter_app/assets/open_source/` 随 APK 打包，包含第三方 notice、仓库地址和 copyleft/source offer。RootFS 中 `/usr/share/doc/**/copyright` 需要继续保留。

`flutter_app/assets/api2py/` 是 CLI 本地中转代理管理页和后端代码，仍属于当前主功能，不要误删。

## 7. 构建与验证

本地 Termux 环境通常没有 Flutter/Dart/adb，APK 编译和 Flutter analyze 依赖 GitHub Actions。普通本地检查包括：

- `npm test`
- `npm run lint -- --no-warn-ignored`
- `git diff --check`
- `bash -n scripts/build-prebuilt-rootfs.sh scripts/prebuilt-rootfs-metadata.sh scripts/fetch-prebuilt-rootfs-asset.sh scripts/publish-prebuilt-rootfs-asset.sh`

下一次真正打包“去 OpenClaw/只保留 CLI 与终端”的 APK 必须使用 Android build `> 208`，并且需要 `rebuild_rootfs=true`，否则 APK 仍可能复用旧 RootFS。
