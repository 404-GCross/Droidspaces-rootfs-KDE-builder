#!/usr/bin/env bash
# DroidDeck Steam 会话：gamescope + Valve 原生 arm64 Steam 客户端（Deck 模式），宿主为 Anland Wayland。
#
# 与 Anland Next 相同：会话本体（Wayland socket 链接 + rootless Xwayland + mini-wm + 会话
# D-Bus）来自 anland-session 包，本 profile 只负责 gamescope、Steam 客户端脚本和会话
# 环境的准备。客户端与 Proton 不在镜像内分发（Valve 许可），由 droiddeck-session 在首次
# 使用时从 Valve CDN 拉取。
set -euo pipefail

source "${ROOTFS_DIR:-}/etc/os-release"

# DroidDeck 上游脚本（Steam 客户端安装、ARM64 Proton 兼容工具注册、每游戏环境变量）。
# 锁 commit 保证构建可复现；DROIDDECK_REPO/DROIDDECK_REF 可在构建时覆盖。
readonly DROIDDECK_REPO="${DROIDDECK_REPO:-404-GCross/DroidDeck}"
readonly DROIDDECK_REF="${DROIDDECK_REF:-6f1fb462edcb7ef65efa70730e4234655f747e6e}"
readonly DROIDDECK_RAW="https://raw.githubusercontent.com/${DROIDDECK_REPO}/${DROIDDECK_REF}"
readonly -a DROIDDECK_SCRIPTS=(
    bannerlator-steam-install
    bannerlator-steam-compat
    bannerlator-game-env
)

# Steam 的 arm64 UI（steamui.so/vgui2_s.so）仍链接 GTK 2，Arch 已不再打包它；
# 同 DroidDeck 运行时：取 Debian 的两个库，只装 soname 需要的两个对象。
readonly GTK2_DEB="libgtk2.0-0t64_2.24.33-7_arm64.deb"
readonly GTK2_SHA="28b2f1622197443f07f25a93e03db1a964184946ac12f501b8221c895026d0ca"
readonly GTK2_URL="http://deb.debian.org/debian/pool/main/g/gtk+2.0/${GTK2_DEB}"

configure_environment() {
    local backend="${1:-}"
    local environment_file="${ROOTFS_DIR:-}/etc/environment"
    local assignment key
    # 只写 Anland 链路真正读取的变量：ANLAND_RUNTIME_DIR 是宿主 runtime dir 的容器视角
    #（droidspaces 绑定挂载到 /run/anland），其余是 kgsl/freedreno 的 GPU 路径。
    # WAYLAND_DISPLAY 故意不写：anland-session 会发布 wayland-anland 链接。
    local -a assignments=(
        XDG_SESSION_TYPE=wayland
        ANLAND_RUNTIME_DIR=/run/anland
        MESA_LOADER_DRIVER_OVERRIDE=kgsl
        GALLIUM_DRIVER=kgsl
        FD_FORCE_KGSL=1
    )

    [[ "$backend" == anland-wayland ]] || {
        echo "DroidDeck Steam 显示后端无效：$backend" >&2
        return 1
    }

    touch "$environment_file"
    for assignment in "${assignments[@]}"; do
        key="${assignment%%=*}"
        grep -q "^${key}=" "$environment_file" || printf '%s\n' "$assignment" >> "$environment_file"
    done
}

install_steam_gtk2() {
    local work
    work="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$work'" RETURN

    curl -fsSL --retry 3 --retry-all-errors -o "$work/$GTK2_DEB" "$GTK2_URL"
    printf '%s  %s\n' "$GTK2_SHA" "$work/$GTK2_DEB" | sha256sum -c --quiet
    (cd "$work" && ar x "$GTK2_DEB" && tar -xf data.tar.*)

    local name
    for name in gtk gdk; do
        install -m 0755 "$work/usr/lib/aarch64-linux-gnu/lib${name}-x11-2.0.so.0.2400.33" /usr/lib/
        ln -sfn "lib${name}-x11-2.0.so.0.2400.33" "/usr/lib/lib${name}-x11-2.0.so.0"
    done
}

install_droiddeck_scripts() {
    local name
    for name in "${DROIDDECK_SCRIPTS[@]}"; do
        curl -fsSL --retry 3 --retry-all-errors \
            -o "/usr/local/bin/$name" \
            "$DROIDDECK_RAW/tools/linuxfs/overlay/usr/local/bin/$name"
        chmod 0755 "/usr/local/bin/$name"
    done
}

install_arch() {
    if [[ "$ID" != "arch" && "$ID" != "archarm" && "$ID" != "archlinux" ]]; then
        echo "DroidDeck Steam 目前只支持 Arch Linux ARM：$ID" >&2
        return 1
    fi

    pacman -S --noconfirm --needed \
        gamescope binutils zstd \
        vulkan-tools mesa-utils mesa-demos \
        dbus libpulse \
        python curl unzip ca-certificates \
        fontconfig freetype2 ttf-dejavu xdg-user-dirs \
        nss libnm openal libvdpau lsof \
        libxcomposite libxdamage libxrandr libxshmfence libxtst libxi libxcb \
        xorg-xkbcomp xkeyboard-config \
        glib2 libglvnd wayland

    install_steam_gtk2
    install_droiddeck_scripts
}

install_profile() {
    case "$ID" in
        arch|archarm|archlinux) install_arch ;;
        *)
            echo "DroidDeck Steam 目前只支持 Arch Linux ARM：$ID" >&2
            return 1
            ;;
    esac
}

case "${1:-install}" in
    install) install_profile ;;
    configure-environment) configure_environment "${2:-}" ;;
    *)
        echo "DroidDeck Steam profile 操作无效：$1" >&2
        exit 1
        ;;
esac
