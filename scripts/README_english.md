English | [中文](README.md) | [Back to project README](../README_english.md)

# scripts Directory

This directory contains installers used while building the RootFS, maintenance tools copied into the RootFS, Android/Termux host launchers, and systemd service templates. Before running a file manually, check whether it belongs in the Linux container, the image build environment, or the Android host.

## File Overview

| File | Run in | Purpose |
| --- | --- | --- |
| `install-mesa.sh` | ARM64 Linux container | Installs the latest Android-container Mesa build and MediaCodec VA-API driver, then locks Mesa, KWin, and Xwayland packages. |
| `install-anland-kde.sh` | ARM64 Linux container | Installs Anland patched KWin/Xwayland Release packages and locks them. |
| `install-usb-manager.sh` | Linux container | Installs Droidspaces USB Manager, distribution dependencies, launchers, and user permissions. |
| `systemd257.sh` | RootFS build environment | Builds a systemd 257 compatibility runtime when required by an old Android kernel. |
| `download-firmware` | Debian/Ubuntu container | Installs `linux-firmware` and decompresses its `.zst` firmware. |
| `nosnap.sh` | Ubuntu RootFS build environment | Removes Snap, prevents reinstallation, and configures traditional deb sources. |
| `on_aaudio_socket.sh` | Rooted Android/Termux host | Starts PulseAudio through a Unix socket, Termux:X11, and container KDE. |
| `on_aaudio_tcp.sh` | Rooted Android/Termux host | Starts PulseAudio over TCP, Termux:X11, and container KDE. |
| `bashrc.sh` | Linux user shell | Adds Docker aliases, thermal helpers, and an SSH file-transfer helper. |
| `start/*.service` | Linux container systemd | Starts Plasma X11, Plasma Wayland, or Plasma Mobile. |
| `binfmt/*` | Linux container systemd/kernel | Checks and mounts `binfmt_misc` for QEMU cross-architecture execution. |

## Mesa Installer

`install-mesa.sh` selects the ARM64 Mesa asset for the current distribution from the latest `lfdevs/mesa-for-android-container` GitHub Release, then installs `msm_drm_drv_video.so` from the latest stable `Re-s/droidspaces-media-decode` Release. It supports Debian 13, Ubuntu 24.04/25.10/26.04, Fedora 43/44, and Arch Linux. Every target installs the media decode driver at `/usr/lib/aarch64-linux-gnu/dri/msm_drm_drv_video.so`.

The installer strictly validates Release tags, asset names, and official download URLs. Mirror downloads of the Mesa archive are verified against the SHA-256 digest published by the GitHub Release API. For every source, the media decode driver is checked against the Release API digest, upstream `SHA256SUMS`, and the published asset size. Downloads can resume, and temporary files are removed on exit.

Run interactively from the repository root:

```bash
sudo ./scripts/install-mesa.sh
```

With no option, the script probes all three sources and prompts for a choice. Select a source directly for unattended builds:

```bash
sudo ./scripts/install-mesa.sh --1  # GitHub
sudo ./scripts/install-mesa.sh --2  # gh-proxy.com
sudo ./scripts/install-mesa.sh --3  # ghproxy.net
```

The source options are mutually exclusive and apply to both the Mesa and media decode driver downloads. `-1`, `-2`, and `-3` are equivalent short options; use `--help` for built-in help. Third-party sources still require access to `api.github.com` for trusted metadata, plus `jq` and `sha256sum`. Downloads use either `curl` or `wget`.

After installation, persistent package locks are written for each distribution:

| Distribution | Lock location and mechanism |
| --- | --- |
| Debian/Ubuntu | `/etc/apt/preferences.d/hold-anland-package` with `Pin-Priority: -1` |
| Fedora | Installer-managed `exclude` block in `/etc/dnf/dnf.conf` |
| Arch | Installer-managed `IgnorePkg` block in `/etc/pacman.conf` |

The lock list is generated from the Mesa packages actually present in the archive and also covers KWin and Xwayland. Managed configuration is idempotent, and unrelated existing configuration is preserved.

## Anland KDE Installer

`install-anland-kde.sh` reads `anland-kde-manifest` from this repository's fixed rolling Release, `anland-kde-packages`, then installs the matching patched KWin/Xwayland packages for Debian 13, Ubuntu 26.04, Fedora 43/44, or Arch Linux on ARM64.

```bash
sudo ./scripts/install-anland-kde.sh
```

It also accepts `--1`, `--2`, or `--3` for GitHub, `gh-proxy.com`, or `ghproxy.net`; with no option, it probes the sources and prompts. Both the manifest and archive from a mirror are checked against GitHub API digests. Messages follow the system locale, and APT holds, DNF excludes, or Pacman `IgnorePkg` entries prevent upgrades from replacing the installed packages.

To install packages published by a fork, override the repository and Release tag:

```bash
sudo ANLAND_KDE_RELEASE_REPOSITORY=owner/repository \
  ANLAND_KDE_RELEASE_TAG=release-tag \
  ./scripts/install-anland-kde.sh --1
```

The Anland host module, app, SELinux policy, bind mount, and Droidspaces permissions must still be configured as described in the [project Wayland and Anland setup](../README_english.md#wayland-and-anland-setup).

## USB Manager Installer

`install-usb-manager.sh` supports Debian/Ubuntu, Fedora, and Arch. It installs PyQt5, ADB, udev, NTFS, exFAT, and other matching dependencies, followed by the `usb-manager`, `usb-passthrough`, and `usb-storage-passthrough` commands.

```bash
sudo ./scripts/install-usb-manager.sh --user "$USER"
```

`--user USER` selects the user that receives USB management permissions and desktop launchers. When omitted, the installer tries `SUDO_USER`, the logged-in user, and then the first regular user. Development and offline tests can use a local Droidspaces-USB-Manager checkout through `--source DIR`; run `--help` for all options.

Hardware access must be enabled when importing the RootFS into Droidspaces, or `/sys/bus/usb` and `/sys/bus/scsi` will not be visible inside the container.

## systemd 257 Compatibility Script

Dockerfiles call `systemd257.sh` when `enable_systemd257=true`. It checks the installed systemd major version: version 257 and older are skipped, while newer systems build a compatibility runtime from the official `v257-stable` branch. Build dependencies are removed afterward, and related systemd packages are locked.

```bash
sudo ./scripts/systemd257.sh
```

This is an experimental, time-consuming build step for old Android kernels. Test systemd, D-Bus, udev, networking, and desktop sessions on the target device before distributing the resulting RootFS.

## Firmware Tool

`download-firmware` is copied to `/usr/local/bin/download-firmware` in Debian 13 and Ubuntu 24/25/26 RootFS images, but it is not run automatically. Run it inside the container when required:

```bash
sudo download-firmware
```

It installs `zstd` and `linux-firmware`, decompresses `.zst` files under `/lib/firmware`, and repairs symlinks that point to compressed files. A successful run creates `/var/lib/.fw-setup-completed`; this marker currently does not skip later runs.

## Other Build and Startup Files

- `nosnap.sh` is Ubuntu-only. It stops and removes Snap, cleans leftovers, writes APT pins that prevent reinstallation, and configures the traditional deb sources required by the project. It changes packages and APT configuration and must run as root in the target RootFS or build layer.
- `on_aaudio_socket.sh` and `on_aaudio_tcp.sh` run on the Android/Termux host, not inside the Linux container. Before use, edit `CONTAINER_NAME`, `USERNAME`, `DISPLAY_NUMBER`, and `DPI` at the top and provide root access, PulseAudio/AAudio, and Termux:X11.
- `start/plasma-x11.service`, `start/plasma-wayland.service`, and `start/plasma-mobile.service` are installed during builds. They start the selected desktop as RootFS UID 1000 and rate-limit restarts after abnormal exits.
- `binfmt/qemu-binfmt-register.sh` and its service verify kernel `binfmt_misc` support and mount it when needed; unsupported kernels are skipped safely. QEMU interpreters are still required for actual cross-architecture execution.
- `bashrc.sh` is shell configuration appended to a user environment, not a standalone installer.

## Development Checks

After changing a shell script, run at least a syntax check. Use ShellCheck when it is installed:

```bash
bash -n scripts/install-mesa.sh
bash -n scripts/install-anland-kde.sh
bash -n scripts/install-usb-manager.sh
shellcheck scripts/install-mesa.sh
```

Changes to package installation or lock handling should also be tested in APT, DNF, and Pacman containers. Run each installer twice to verify idempotency.
