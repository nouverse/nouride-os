#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Nouride OS — Armbian Chroot Customization Script
# Runs inside the target rootfs during the final stage of Armbian image build.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

echo "======================================================================"
echo " Executing Nouride OS customization hook..."
echo "======================================================================"

# 1. Hostname & Networking
echo "nouride-box" > /etc/hostname
sed -i 's/127\.0\.1\.1.*/127.0.1.1\tnouride-box/g' /etc/hosts || echo -e "\n127.0.1.1\tnouride-box" >> /etc/hosts

# 2. Flash Storage Hardening (Volatile Journald)
mkdir -p /etc/systemd/journald.conf.d
cat <<'EOF' > /etc/systemd/journald.conf.d/volatile.conf
[Journal]
Storage=volatile
RuntimeMaxUse=32M
RuntimeKeepFree=64M
MaxRetentionSec=3day
EOF

# 3. Memory & ZRAM Tuning (0 Swap to Flash, Compressed RAM Swap Only)
if [ -f /etc/default/zramswap ]; then
  sed -i 's/^#*ALLOCATION=.*/ALLOCATION=50/' /etc/default/zramswap
  sed -i 's/^#*PRIORITY=.*/PRIORITY=100/' /etc/default/zramswap
fi

# Disable traditional disk swap partitions
systemctl mask dphys-swapfile.service 2>/dev/null || true

# 4. Clock and Time Synchronization (Handle No-RTC STBs)
systemctl enable fake-hwclock.service 2>/dev/null || true
systemctl enable systemd-time-wait-sync.service 2>/dev/null || true

# 5. Dedicated User & Directory Setup
if ! id "nouride" >/dev/null 2>&1; then
  useradd -m -d /srv/nouride -s /bin/bash -c "Nouride Daemon" nouride
  usermod -aG sudo,netdev nouride
fi
mkdir -p /srv/nouride/.nouride/bin /srv/nouride/.nouride/data /srv/nouride/.nouride/home
chown -R nouride:nouride /srv/nouride

# 6. Install Nouride Daemon (Standalone arm64)
echo "Installing Nouride daemon..."
INSTALL_URL="https://nouride.com/install.sh"
if curl -fsSL "${INSTALL_URL}" -o /tmp/install-nouride.sh; then
  chmod +x /tmp/install-nouride.sh
  su - nouride -c "bash /tmp/install-nouride.sh --appliance" || true
  rm -f /tmp/install-nouride.sh
fi

# 7. Install Hardened Systemd Service
cat <<'EOF' > /etc/systemd/system/nouride.service
[Unit]
Description=Nouride Multi-Agent AI Daemon
After=network-online.target systemd-time-wait-sync.service
Wants=network-online.target systemd-time-wait-sync.service

[Service]
Type=simple
User=nouride
Group=nouride
WorkingDirectory=/srv/nouride
ExecStart=/srv/nouride/nouride start
Restart=always
RestartSec=3s
KillMode=mixed
TimeoutStopSec=15s

# Sandboxing and Resource Hardening
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=read-only
ReadWritePaths=/srv/nouride /tmp
MemoryHigh=1600M
MemoryMax=1800M
TasksMax=1024

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nouride.service

# 8. Clean Up & Seal Image
rm -f /etc/ssh/ssh_host_*
rm -f /etc/machine-id
touch /etc/machine-id
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

echo "Nouride OS customization completed successfully."
