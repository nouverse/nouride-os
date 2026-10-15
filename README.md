# Nouride OS

Official appliance operating system overlay for **Nouride Box** on ARM Single Board Computers (SBCs) and TV boxes, including **Orange Pi Zero 2 / 3 (Allwinner H616/H618)** and **Amlogic S905X2 (e.g. ZTE B860H v5.0)**.

---

## Architectural Philosophy: Zero Hard-Forks

Nouride OS **does not** fork the Armbian kernel repository. Instead, it uses Armbian's official external `userpatches/` overlay architecture. All device tree compilation, upstream Linux kernel security patches, and bootloader (U-Boot) toolchains are inherited directly from pinned Armbian releases (`compile.sh docker`), while Nouride-specific hardening and daemon payloads are baked via chroot hooks.

### What Nouride OS Configures on the Base System:
1. **Flash Storage Hardening:**
   - `systemd-journald` configured with `Storage=volatile` (logs in RAM, zero MicroSD/eMMC wear).
   - Zero swap to physical flash; dynamic compressed RAM swap via `systemd-zram-generator` (zram).
   - Nightly SQLite backup rotation and flash-safe autocheckpoints.
2. **Clock & NTP Synchronization:**
   - `fake-hwclock` installed and `systemd-time-wait-sync` enabled (STBs lack RTC hardware; prevents clock regressions from misfiring scheduled cron jobs).
3. **Network & Provisioning:**
   - `NetworkManager` exclusively for network management.
   - Built-in Wi-Fi Access Point fallback for zero-terminal smartphone onboarding (`Nouride-Setup-XXXX`).
4. **Daemon Lifecycle:**
   - Dedicated unprivileged system user `nouride` (`/srv/nouride`).
   - Hardened `nouride.service` systemd unit with auto-restart, cgroup memory limits (`MemoryHigh`), and security sandboxing.

> **Note on Raspberry Pi Zero 2 W:**
> Raspberry Pi Zero 2 W is **not** built via Armbian. It uses the official Raspberry Pi OS Lite 64-bit pipeline with cloud-init injection implemented in `nouride/internals/pro/build-pro/flash/`.

---

## Hardware Targets & Presets

| Target Preset | SoC / Architecture | Target Hardware | Supported By |
| :--- | :--- | :--- | :--- |
| `aml-s9xx-box` | Amlogic S905X2 (ARM64) | ZTE B860H v5.0, HG680P, X96 Max | Armbian Community |
| `orangepi-zero3` | Allwinner H618 (ARM64) | Orange Pi Zero 3 (1GB / 2GB / 4GB) | Armbian Official (Tier 1) |
| `orangepi-zero2` | Allwinner H616 (ARM64) | Orange Pi Zero 2 (1GB) | Armbian Official (Tier 1) |

---

## How to Build

Building Nouride OS requires **Docker** on any Linux x86_64 host or macOS.

### 1. Build an Image via Docker
```bash
# Build for Amlogic S905X2 TV Box (ZTE B860H)
./build.sh aml-s9xx-box

# Build for Orange Pi Zero 3
./build.sh orangepi-zero3

# Build for Orange Pi Zero 2
./build.sh orangepi-zero2
```

The script will:
1. Clone `armbian/build` pinned to release tag `v26.2.1` into `armbian-build/` if not present.
2. Mount `userpatches/` and board configs into the Armbian Docker container.
3. Build the minimal Debian 13 (Trixie) image.
4. Execute `userpatches/customize-image.sh` inside chroot to install the Nouride daemon and configure hardening.
5. Output the ready-to-flash compressed image (`.img.xz`) and SHA256 checksum to `output/images/`.

### 2. Flashing the Image
Burn the output image to a MicroSD card using `dd`, Raspberry Pi Imager, or BalenaEtcher:
```bash
xz -dc output/images/nouride-os-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

---

## Repository Structure

```
nouride-os/
├── README.md
├── build.sh                      # One-command Docker build entrypoint
├── configs/                      # Board preset configurations
│   ├── aml-s9xx-box.conf         # Amlogic TV Box (S905X2 / B860H)
│   ├── orangepi-zero2.conf       # Orange Pi Zero 2 (H616)
│   └── orangepi-zero3.conf       # Orange Pi Zero 3 (H618)
└── userpatches/                  # Armbian build overlay
    ├── config-default.conf       # Global minimal OS build flags
    ├── customize-image.sh        # Chroot hook: hardening, daemon install, services
    └── overlay/                  # Files copied verbatim to rootfs
        └── etc/
            ├── issue             # Pre-login console banner
            ├── motd              # Post-login SSH banner
            └── systemd/system/
                └── nouride.service # Hardened systemd daemon unit
```
