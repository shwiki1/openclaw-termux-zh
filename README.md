<div align="center">
  <img src="assets/ic_launcher.png" alt="次元虾" width="160" />
  <h1>次元虾</h1>
  <p>
    <a href="README.md">简体中文</a> | <a href="docs/README_en.md">English</a>
  </p>
  <p>面向中文 Android 用户维护的 OpenClaw 独立整合应用。</p>
  <p>
    <img src="https://img.shields.io/badge/Release-v2.0.50-2563EB?style=for-the-badge" alt="Release v2.0.50" />
    <img src="https://img.shields.io/badge/Package-com.agent.cyx-111827?style=for-the-badge" alt="Package com.agent.cyx" />
    <img src="https://img.shields.io/badge/Android-10%2B-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android" />
    <img src="https://img.shields.io/badge/License-MIT-111827?style=for-the-badge" alt="License" />
  </p>
  <p>
    <img src="https://img.shields.io/badge/Flutter-App_Shell-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter" />
    <img src="https://img.shields.io/badge/Kotlin-Android_Service-7F52FF?style=flat-square&logo=kotlin&logoColor=white" alt="Kotlin" />
    <img src="https://img.shields.io/badge/Ubuntu-RootFS-E95420?style=flat-square&logo=ubuntu&logoColor=white" alt="Ubuntu" />
    <img src="https://img.shields.io/badge/Node.js-Runtime-339933?style=flat-square&logo=nodedotjs&logoColor=white" alt="Node.js" />
    <img src="https://img.shields.io/badge/OpenClaw-Gateway-0F172A?style=flat-square" alt="OpenClaw" />
  </p>
</div>

> 本仓库为社区维护项目，不代表 OpenClaw 官方 Android 发布渠道。升级或覆盖安装前，请自行评估兼容性、数据备份和安全风险。

## 当前版本

- 应用名：`次元虾`
- Android 包名：`com.agent.cyx`
- 版本名：`2.0.50`
- 构建号：`135`
- 发布产物前缀：`CiYuanXia-v`
- Dart 包名仍保留为 `openclaw`，用于兼容现有 Flutter 测试导入。

## 项目定位

次元虾的目标是在 Android 手机上直接运行 OpenClaw Gateway，不依赖 Termux App，也不要求 Root 权限。应用通过 PRoot 创建 Ubuntu RootFS，在其中部署 Node.js 和 OpenClaw，再由 Flutter 与 Kotlin 原生层提供安装、配置、日志、前台服务和设备能力桥接。

核心能力：

- 一键初始化 Ubuntu RootFS、Node.js 与 OpenClaw。
- 中文安装向导、首页、配置编辑器、日志和备份中心。
- AI 提供商、消息平台、可选组件、节点能力管理。
- OpenClaw Gateway 前台服务、日志持久化和自动重启。
- 本地模型入口：下载 llama.cpp runtime、管理 GGUF 模型并测试本地对话。
- 备份导出、备份库切换、配置恢复和工作目录恢复。

## 架构概览

```text
Flutter UI
  -> MethodChannel / EventChannel
Kotlin Android services
  -> PRoot process manager
Ubuntu RootFS
  -> Node.js 24.14.1 / OpenClaw Gateway / CLI tools
Android device capabilities
  -> camera / location / screen / flash / vibration / sensors / serial
```

主要目录：

- `flutter_app/`：Flutter Android 应用主线。
- `flutter_app/android/`：Kotlin 原生桥、前台服务、PRoot 进程管理和 Android 配置。
- `flutter_app/lib/`：页面、状态管理、安装流程、Gateway、节点能力、CLI 工具和本地模型服务。
- `flutter_app/assets/bootstrap/`：基础运行时资源或 Git LFS 指针。
- `scripts/`：APK 构建、RootFS 构建、资源发布和辅助脚本。
- `lib/`、`bin/`：旧 Node CLI 兼容入口。
- `release/`：历史发布说明。

## 运行时资源

当前版本不应依赖 APK 内置完整大体积运行时。初始化时会按顺序使用：

1. 已恢复的 `basic-resource` 资源。
2. 用户填写的资源 URL。
3. 用户选择的本地压缩包。
4. 在线镜像下载。

当前默认资源策略：

- Ubuntu：`24.04.3 noble`
- arm64 / x86_64：Node.js `24.14.1`
- armv7 / armhf：Node.js `22.22.2`
- OpenClaw：默认选择 npm `openclaw@latest` 的稳定版，过滤 beta、rc、test、preview 等预发布版本。

## 重要提醒

- `assets/bootstrap/openclaw-rootfs-noble-arm64.tar.gz` 可能是 Git LFS 指针，构建前必须恢复真实资源，或由 CI 从 `basic-resource` Release 拉取。
- 长时间运行 Gateway 时建议关闭系统电池优化，并授予必要存储权限。
- 恢复工作目录备份会覆盖 `/root/.openclaw` 下的核心数据，恢复前请确认备份来源可信。
- Canvas capability 当前仍是未实现占位，不能按已可用能力使用。

## 构建

源码构建：

```bash
cd flutter_app
flutter pub get
flutter build apk --release
```

生成发布目录：

```bash
python scripts/build_release.py --version 2.0.50 --build-number 135
```

GitHub Actions 构建产物命名：

```text
CiYuanXia-v2.0.50-135-arm64-v8a.apk
```

## 验证

当前 Termux 环境可执行的验证：

```bash
npm test
node node_modules/eslint/bin/eslint.js . --no-warn-ignored
```

完整 Android 验证需要带 Flutter SDK / Android SDK 的环境：

```bash
cd flutter_app
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## 上游来源

- Android 集成上游：[`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
- 汉化基础分支：[`TIANLI0/openclaw-termux` 的 `feature/translation` 分支](https://github.com/TIANLI0/openclaw-termux/tree/feature/translation)
- OpenClaw 核心项目：[`openclaw/openclaw`](https://github.com/openclaw/openclaw)

## 文档

- [CHANGELOG.md](CHANGELOG.md)
- [STRUCTURE.md](STRUCTURE.md)
- [docs/README_en.md](docs/README_en.md)
- [docs/jsonl_format_guide.md](docs/jsonl_format_guide.md)

## 许可证

MIT，详见 [LICENSE](LICENSE)。
