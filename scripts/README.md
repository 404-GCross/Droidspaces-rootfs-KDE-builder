中文 | [English](README_english.md) | [返回项目主页](../README.md)

# scripts 目录说明

本目录存放 RootFS 构建期间使用的安装器、写入 RootFS 的维护工具、Termux/Android 宿主侧启动脚本，以及 systemd 服务模板。多数文件由 Dockerfile 或 GitHub Actions 调用；运行前请先确认脚本应在 Linux 容器、构建环境还是 Android/Termux 宿主中执行。

## 文件一览

| 文件 | 运行位置 | 作用 |
| --- | --- | --- |
| `install-mesa.sh` | ARM64 Linux 容器 | 安装最新版 Android 容器专用 Mesa 和 MediaCodec VA-API 驱动，并锁定 Mesa、KWin 和 Xwayland 包。 |
| `install-anland-kde.sh` | ARM64 Linux 容器 | 安装 Anland patched KWin/Xwayland Release 包，并锁定相关包。 |
| `install-usb-manager.sh` | Linux 容器 | 安装 Droidspaces USB Manager、发行版依赖、菜单入口和用户权限。 |
| `systemd257.sh` | RootFS 构建环境 | 在需要时构建 systemd 257 兼容运行时，供旧 Android 内核使用。 |
| `download-firmware` | Debian/Ubuntu 容器 | 安装并解压 `linux-firmware` 中的 `.zst` 固件。 |
| `nosnap.sh` | Ubuntu RootFS 构建环境 | 移除 Snap、阻止其重新安装，并配置传统 deb 软件源。 |
| `on_aaudio_socket.sh` | 已 root 的 Android/Termux | 通过 Unix socket 启动 PulseAudio、Termux:X11 和容器 KDE。 |
| `on_aaudio_tcp.sh` | 已 root 的 Android/Termux | 通过 TCP 启动 PulseAudio、Termux:X11 和容器 KDE。 |
| `bashrc.sh` | Linux 用户 shell | 提供 Docker 快捷命令、温度查看和 SSH 文件传输等辅助函数。 |
| `start/*.service` | Linux 容器的 systemd | 分别自动启动 Plasma X11、Plasma Wayland 和 Plasma Mobile。 |
| `binfmt/*` | Linux 容器的 systemd/内核 | 检查并挂载 `binfmt_misc`，为 QEMU 跨架构执行做准备。 |

## Mesa 安装器

`install-mesa.sh` 从 `lfdevs/mesa-for-android-container` 的最新 GitHub Release 选择当前发行版对应的 ARM64 Mesa 资产，并从 `Re-s/droidspaces-media-decode` 的最新稳定 Release 安装 `msm_drm_drv_video.so`。支持 Debian 13、Ubuntu 24.04/25.10/26.04、Fedora 43/44 和 Arch Linux；所有系统都将媒体解码驱动安装到 `/usr/lib/aarch64-linux-gnu/dri/msm_drm_drv_video.so`。

安装器会严格检查 Release tag、资产名和官方下载地址。使用镜像源时，Mesa 归档会根据 GitHub Release API 公布的 SHA-256 digest 校验；媒体解码驱动在所有下载源下都会校验 Release API digest、上游 `SHA256SUMS` 及资产大小。下载支持断点续传，临时文件在退出时自动清理。

从仓库根目录交互运行：

```bash
sudo ./scripts/install-mesa.sh
```

未指定参数时，脚本会测试三个下载源并提示选择。也可以直接指定来源，适合无人值守构建：

```bash
sudo ./scripts/install-mesa.sh --1  # GitHub
sudo ./scripts/install-mesa.sh --2  # gh-proxy.com
sudo ./scripts/install-mesa.sh --3  # ghproxy.net
```

三个来源选项互斥，并同时作用于 Mesa 与媒体解码驱动下载。`-1`、`-2`、`-3` 是对应的短参数，`--help` 可查看内置帮助。第三方源仍需访问 `api.github.com` 取得可信元数据，并需要 `jq` 和 `sha256sum`；下载由 `curl` 或 `wget` 完成。

安装完成后，脚本按发行版写入持久锁定：

| 发行版 | 锁定位置与机制 |
| --- | --- |
| Debian/Ubuntu | `/etc/apt/preferences.d/hold-anland-package`，`Pin-Priority: -1` |
| Fedora | `/etc/dnf/dnf.conf` 中脚本管理的 `exclude` 块 |
| Arch | `/etc/pacman.conf` 中脚本管理的 `IgnorePkg` 块 |

锁定范围根据归档中实际安装的 Mesa 包生成，并加入 KWin 与 Xwayland。托管配置可重复运行，不会不断追加相同块；已有的非托管配置会保留。

## Anland KDE 安装器

`install-anland-kde.sh` 从本仓库固定滚动 Release `anland-kde-packages` 读取 `anland-kde-manifest`，为 Debian 13、Ubuntu 26.04、Fedora 43/44 或 Arch Linux ARM64 安装匹配版本的 patched KWin/Xwayland 包。

```bash
sudo ./scripts/install-anland-kde.sh
```

它同样支持 `--1`、`--2`、`--3` 选择 GitHub、`gh-proxy.com` 或 `ghproxy.net`；省略时测速后交互选择。镜像下载的清单与归档均使用 GitHub API digest 校验。脚本按系统 locale 输出中文或英文，并通过 APT hold、DNF exclude 或 Pacman `IgnorePkg` 防止系统更新覆盖安装结果。

安装 fork 发布的包时可以覆盖仓库和 Release tag：

```bash
sudo ANLAND_KDE_RELEASE_REPOSITORY=owner/repository \
  ANLAND_KDE_RELEASE_TAG=release-tag \
  ./scripts/install-anland-kde.sh --1
```

Anland 宿主模块、App、SELinux、绑定挂载和 Droidspaces 权限仍需按[项目主页的 Wayland 和 Anland 配置](../README.md#wayland-和-anland-配置)完成。

## USB Manager 安装器

`install-usb-manager.sh` 支持 Debian/Ubuntu、Fedora 和 Arch，自动安装 PyQt5、ADB、udev、NTFS、exFAT 等依赖，并安装 `usb-manager`、`usb-passthrough` 和 `usb-storage-passthrough` 命令。

```bash
sudo ./scripts/install-usb-manager.sh --user "$USER"
```

`--user USER` 指定获得 USB 管理权限和桌面入口的用户。省略时依次尝试 `SUDO_USER`、当前登录用户和第一个普通用户。开发或离线测试可以通过 `--source DIR` 使用本地 Droidspaces-USB-Manager 源码目录；运行 `--help` 查看完整参数。

RootFS 导入 Droidspaces 时必须开启硬件访问，否则容器无法看到 `/sys/bus/usb` 和 `/sys/bus/scsi`。

## systemd 257 兼容脚本

`systemd257.sh` 供 Dockerfile 在 `enable_systemd257=true` 时调用。它检查已安装的 systemd 主版本：257 或更低版本直接跳过，更高版本则从官方 `v257-stable` 构建兼容运行时。构建完成后清理依赖并锁定 systemd 相关包。

```bash
sudo ./scripts/systemd257.sh
```

这是面向旧 Android 内核的实验性构建步骤，耗时较长。生成 RootFS 后应实际验证 systemd、D-Bus、udev、网络和桌面会话。

## 固件工具

`download-firmware` 会被复制为 Debian 13 和 Ubuntu 24/25/26 RootFS 中的 `/usr/local/bin/download-firmware`，但不会自动执行。需要时在容器中运行：

```bash
sudo download-firmware
```

脚本安装 `zstd` 和 `linux-firmware`，解压 `/lib/firmware` 下的 `.zst` 文件，并修复指向压缩文件的软链接。成功后创建 `/var/lib/.fw-setup-completed`；该标记目前不用于跳过重复运行。

## 其他构建和启动文件

- `nosnap.sh` 仅用于 Ubuntu。它停止并卸载 Snap、清理残留、写入 APT pin 防止重新安装，并配置项目所需的传统 deb 来源。它会修改系统软件包和 APT 配置，应在目标 RootFS 或构建层中以 root 运行。
- `on_aaudio_socket.sh` 和 `on_aaudio_tcp.sh` 在 Android/Termux 宿主运行，不是在 Linux 容器内运行。使用前修改文件顶部的 `CONTAINER_NAME`、`USERNAME`、`DISPLAY_NUMBER` 和 `DPI`，并准备 root、PulseAudio/AAudio 与 Termux:X11。
- `start/plasma-x11.service`、`start/plasma-wayland.service` 和 `start/plasma-mobile.service` 是构建时安装的服务模板，以 RootFS 的 UID 1000 用户启动对应桌面，并对异常退出进行限频重启。
- `binfmt/qemu-binfmt-register.sh` 与对应 service 检查内核是否支持 `binfmt_misc`，必要时挂载它；不支持时安全跳过。实际跨架构执行仍需要 QEMU 解释器。
- `bashrc.sh` 是追加到用户 shell 环境的辅助配置，不应作为独立安装器执行。

## 开发检查

修改 shell 脚本后，至少运行语法检查；安装了 ShellCheck 时也应执行静态检查：

```bash
bash -n scripts/install-mesa.sh
bash -n scripts/install-anland-kde.sh
bash -n scripts/install-usb-manager.sh
shellcheck scripts/install-mesa.sh
```

涉及软件包安装和锁定配置的改动，还应分别在 APT、DNF 和 Pacman 容器中验证，并重复运行一次检查幂等性。
