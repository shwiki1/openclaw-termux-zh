# basic-resource

这是 `次元虾` / OpenClaw Android 中文整合版复用的基础运行时资源 Release，不是 App 正式版本发布页。

建议保持：

- Tag：`basic-resource`
- Release title：`basic-resource`
- 不要勾选 `Set as the latest release`
- 只作为安装向导和云构建复用的资源附件页面

## 当前资源内容

当前 arm64 预构建 RootFS 由构建脚本自动生成，并在清单里记录本次实际解析到的上游版本。当前预期组件为：

- Ubuntu Base：`24.04.3 (noble)`
- Node.js：`24.15.0`
- OpenClaw：`2026.7.1`
- `@tencent-connect/openclaw-qqbot`：`2.0.0`
- `@tencent-weixin/openclaw-weixin`：`2.4.6`

如果后续 `openclaw@latest` 或插件 `latest` 再变化，构建流程会因为清单指纹不再匹配而自动重建并重新发布，不再继续误复用旧包。

## 附件说明

- `openclaw-rootfs-noble-arm64.tar.gz`
  - arm64 预构建 Ubuntu RootFS，已包含基础 apt 包、Node.js、OpenClaw 和常用消息插件。
- `openclaw-rootfs-noble-arm64.json`
  - 与预构建 RootFS 配套的清单文件，记录实际解析版本、校验指纹、SHA256 和构建时间。
- `ubuntu-base-24.04.3-base-arm64.tar.gz`
  - 标准 Ubuntu base RootFS 兜底资源；预构建包失效时，安装流程仍可退回标准初始化链路。

## App 内使用方式

首次启动默认优先使用安装包内已经打包好的预构建资源；如果用户进入“预构建资源配置”并点击“使用 GitHub 资源”，应用会填入当前 Release 的资源链接作为覆盖配置。

若预构建 RootFS 解压、校验或基础包检测失败，应用会自动回退到标准 Ubuntu base RootFS 初始化流程，再按需要下载 Node.js 与 OpenClaw。

## 使用提醒

1. 这些预构建附件当前只覆盖 arm64 设备。
2. 资源体积较大，建议在 Wi-Fi 环境下下载或复用。
3. 需要精确校验时，以 `openclaw-rootfs-noble-arm64.json` 中的 `archive_sha256` 和 `archive_size` 为准。
4. 如果只需要快速初始化，优先使用 `openclaw-rootfs-noble-arm64.tar.gz`；标准 Ubuntu base 主要用于失败回退和手动兜底。
