[文档目录](README.md) · [项目主页](../../README.md)

# 桌面启动与 Anland Wayland

## 桌面自动启动

启用 `desktop_autostart` 后，RootFS 会安装 `desktop-session.service`。它以 UID 1000 的普通用户运行，并读取 `/etc/droidspaces-desktop.conf` 选择会话。

| 桌面与后端 | 手动启动命令 |
| --- | --- |
| KDE + X11 | `DISPLAY=:5 startplasma-x11` |
| KDE + Anland Wayland | `startplasma-wayland` |
| KDE Mobile + Anland Wayland | `startplasmamobile` |
| GNOME + Anland Wayland | `gnome-session --session=gnome` |
| Anland Next | `/usr/bin/anland-session` |
| Niri | `/usr/bin/niri-anland` |
| DroidDeck Steam | `/usr/local/bin/droiddeck-session` |

服务在桌面异常退出后等待 2 秒重启；60 秒内连续失败超过 5 次会暂停重试。正常退出不会触发重启。

### X11

X11 桌面使用 `DISPLAY=:5`，需要在 Android 端安装并启动 Termux:X11。若关闭自动启动，可在容器内运行：

```bash
startplasma-x11
```

### Wayland 和 Anland 宿主端配置

Anland Wayland 支持 Debian 13、Ubuntu 26、Fedora 43/44 和 Arch。KDE 使用 patched KWin/Xwayland，GNOME 使用 patched Mutter。Debian、Ubuntu 和 Arch 的 GNOME 包均由 [`droidspaces-package`](https://github.com/Goldzxcbug/droidspaces-package) 发布，RootFS 构建时从对应 Release 安装。Arch 的 Niri 会话使用 `niri-anland` 与同一 Release 中的 patched Xwayland，并安装 `xdg-desktop-portal-gtk` 和 Alacritty 终端。

Niri 启动时检查 `/run/display.sock` 与 `xwayland-satellite`，并设置 Anland legacy 显示后端变量。启动脚本直接运行 `/usr/bin/niri-anland`，不使用 `--session`。

在 Android 设备上完成以下准备：

1. 从 [Anland Releases](https://github.com/superturtlee/anland/releases) 下载并安装设备对应的 `virtual-drm-daemon.zip`，按该项目说明刷入并重启设备。
2. 从同一 Release 下载并安装 `app-debug.apk`。
3. 在 Droidspaces 容器设置中开启硬件访问。
4. 为容器启用特权模式，并开启 `nocaps`、`noseccomp`。
5. 按设备策略配置 SELinux；可启用宽容模式，或只允许 Anland 显示服务访问所需的 socket。
6. 在高级选项中添加绑定挂载：

   ```text
   /data/local/tmp/display_daemon.sock -> /run/display.sock
   ```

启动容器并以普通用户登录。KDE 可手动运行 `startplasma-wayland`；KDE Mobile 使用 `startplasmamobile`；GNOME 使用 `gnome-session --session=gnome`。

### DroidDeck Steam 宿主端配置（Anland 6.x）

DroidDeck Steam 会话走 Anland 6.x 的 `anland-awl`（Wayland host），与上面 KDE/GNOME/Niri 使用的
legacy `virtual-drm-daemon` 不是同一套，宿主端按下面准备：

1. 从 [Anland Releases](https://github.com/SuperTurtleDev/anland/releases) 下载 6.x 构建包，
   刷入 `module/anland-awl.zip`（KernelSU/SukiSU 模块），安装 `anland-wayland.apk`，重启设备。
2. 容器设置：开启硬件访问；按设备情况启用特权模式与 `nocaps`、`noseccomp`。
3. 添加绑定挂载（注意与 legacy 的 `/run/display.sock` 不同）：

   ```text
   /data/local/tmp/awl -> /run/anland
   ```

启动容器后由 `desktop-session.service` 自动运行 `/usr/local/bin/droiddeck-session`；手动启动
同样使用该命令。首次启动会从 Valve 拉取原生 arm64 Steam 客户端，并注册 ARM64 Proton 兼容工具。

### 安装或更新 Anland 桌面组件

构建时会自动获取匹配包。若要在已运行的 ARM64 RootFS 中单独安装，可从仓库根目录执行：

```bash
sudo ./scripts/tui/install-anland-kde.sh
```

GNOME 安装器可在 Debian 13、Ubuntu 26 与 Arch Linux ARM 上使用：

```bash
sudo ./scripts/tui/install-anland-gnome.sh
```

GNOME 安装器已支持 Arch pacman 包格式，并从 `anland-gnome-packages` Release 清单读取 Arch 目标。

安装器选项、下载源和校验方式见[脚本说明](../../scripts/README.md#anland-kde-安装器)。
