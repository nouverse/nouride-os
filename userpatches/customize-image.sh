#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Nouride OS — Armbian Chroot Customization Script
# Runs as root inside the target rootfs (arm64 under qemu-user on x86 hosts), with no systemd or D-Bus.
# Args from Armbian: $1=RELEASE $2=LINUXFAMILY $3=BOARD $4=BUILD_DESKTOP $5=ARCH
# userpatches/overlay is bind-mounted READ-ONLY at /tmp/overlay: nothing in it reaches the image unless it
# is copied here, and /tmp must never be wiped wholesale. Any non-zero exit fails the build, so nothing
# below is allowed to fail quietly.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

BOARD="$3"
OVERLAY=/tmp/overlay
NR_DIR=/srv/nouride
PAYLOAD="${OVERLAY}/nouride/nouride-linux-arm64.tar.gz"

echo "Executing Nouride OS customization hook (${BOARD})"

# 1. Static files: overlay/rootfs/ -> /. Root-owned whatever UID the build host checked them out as, modes
#    normalised to 0644/0755, and --no-overwrite-dir keeps the modes of existing directories like / and /etc.
if [ -d "${OVERLAY}/rootfs" ]; then
  tar -C "${OVERLAY}/rootfs" --owner=0 --group=0 --mode='u=rwX,go=rX' -cf - . | tar -C / --no-overwrite-dir -xf -
fi

# 2. Access. Armbian ships root:1234 with PermitRootLogin yes, and its first-login wizard only runs on an
#    interactive TTY login, which an appliance never gets. Console autologin is off in config-nouride.conf.
passwd --lock root
rm -f /root/.not_logged_in_yet
install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/10-nouride.conf <<'EOF'
# Drop-ins are read before sshd_config and the first value wins, so this beats Armbian's PermitRootLogin yes.
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF

# 3. Clock. trixie's fake-hwclock 0.14 inverts load's FORCE test (Debian #1093227): by default it sets the clock
#    to the saved time even when that moves it backwards. FORCE=true restores the documented forward-only
#    behaviour; drop this line once 0.15 reaches trixie, where FORCE=true means "either direction".
echo 'FORCE=true' > /etc/default/fake-hwclock

# 4. Boot robustness: repair the rootfs unattended instead of dropping a headless box into an emergency shell.
if [ -f /boot/armbianEnv.txt ]; then
  if grep -q '^extraargs=' /boot/armbianEnv.txt; then
    sed -i '/^extraargs=/ s/$/ fsck.repair=yes/' /boot/armbianEnv.txt
  else
    echo 'extraargs=fsck.repair=yes' >> /boot/armbianEnv.txt
  fi
fi

# 5. Amlogic boxes boot Linux only by chainloading /boot/u-boot.ext (s905_autoscript); without it the vendor
#    u-boot falls through to Android. Pick the blob that matches the DTB this image was built with.
if [ "${BOARD}" = "aml-s9xx-box" ]; then
  case "$(grep -m1 -o 'meson-[a-z0-9]*' /boot/extlinux/extlinux.conf)" in
    meson-gxl | meson-gxm) cp /boot/u-boot-s905x-s912 /boot/u-boot.ext ;;
    meson-g12a | meson-g12b) cp /boot/u-boot-s905x2-s922 /boot/u-boot.ext ;;
    meson-sm1) cp /boot/u-boot-s905x3 /boot/u-boot.ext ;;
    *) echo "unrecognised Amlogic DTB in extlinux.conf; refusing to guess u-boot.ext" >&2; exit 1 ;;
  esac
fi

# 6. Nouride, from the payload build.sh pinned and checksummed on the host (re-checked here so a stale or
#    partial copy can't ship). install.sh is not run in the chroot: it has no --appliance flag, refuses to run
#    as non-root, executes the arm64 binary under emulation, and sizes the unit from the build host's RAM.
(cd "${OVERLAY}/nouride" && sha256sum --check --strict nouride-linux-arm64.tar.gz.sha256)
id nouride >/dev/null 2>&1 || useradd --system --no-create-home --home-dir "${NR_DIR}" --shell /usr/sbin/nologin --comment "Nouride daemon" nouride
install -d -o nouride -g nouride -m 0755 "${NR_DIR}"
STAGE="$(mktemp -d)"
tar -xzf "${PAYLOAD}" -C "${STAGE}" --no-same-owner
[ -x "${STAGE}/nouride" ] || { echo "payload has no nouride executable" >&2; exit 1; }
for item in nouride dashboard skills wa-bridge frontend config.example.toml; do
  if [ -e "${STAGE}/${item}" ]; then cp -a "${STAGE}/${item}" "${NR_DIR}/"; fi
done
rm -rf "${STAGE}"
install -d -o nouride -g nouride -m 0750 "${NR_DIR}/.nouride" "${NR_DIR}/.nouride/data"
install -d -o nouride -g nouride -m 0700 "${NR_DIR}/.nouride/home"
# Nothing in .env is required, but without HOST the dashboard binds 127.0.0.1 only and cron runs in UTC.
if [ ! -f "${NR_DIR}/.env" ]; then
  printf 'HOST=0.0.0.0\nTZ=Etc/UTC\n' > "${NR_DIR}/.env"
fi
chmod 0600 "${NR_DIR}/.env"
# The daemon updates itself in place, so it owns its install dir.
chown -R nouride:nouride "${NR_DIR}"

# 7. Service: overlay/rootfs/etc/systemd/system/nouride.service, copied in step 1 (the installer's own unit,
#    plus RAM-relative MemoryHigh, OOMPolicy=continue and more sandboxing; never ordered after time sync).
systemctl enable nouride.service

# 8. Seal: an empty machine-id gets a fresh one at boot (identity is machine-id + SoC serial). "uninitialized"
#    or a missing file would instead trigger first-boot preset-all, enabling units with no preset rule.
: > /etc/machine-id
rm -f /var/lib/dbus/machine-id

echo "Nouride OS customization completed successfully."
