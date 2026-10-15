#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Nouride OS — Armbian Overlay Build Entrypoint
# ─────────────────────────────────────────────────────────────────────────────

# A tag can be moved upstream; the commit cannot. Bump both together.
ARMBIAN_TAG="v26.2.1"
ARMBIAN_COMMIT="efb4c684c67cde3b2ba484a5b9e1bb1ab3d7eee6"
# The release's SHA256SUMS is unsigned and served from the same origin, so the hash is pinned here instead.
NOURIDE_VERSION="v0.7.2"
NOURIDE_ARM64_SHA256="5626358262257391a602fadd3c0ba320ae622b0f764a1c0799aa1547a87ce780"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARMBIAN_DIR="${SCRIPT_DIR}/armbian-build"
CONFIGS_DIR="${SCRIPT_DIR}/configs"
USERPATCHES_DIR="${SCRIPT_DIR}/userpatches"

function usage() {
  echo "Usage: ./build.sh <target-preset>"
  echo ""
  echo "Available presets in configs/:"
  for cfg in "${CONFIGS_DIR}"/*.conf; do
    [ -f "${cfg}" ] && basename "${cfg}" .conf | sed 's/^/  - /'
  done
  exit 1
}

TARGET="${1:-}"
[[ "${TARGET}" =~ ^[a-z0-9-]+$ ]] || usage
TARGET_CONF="${CONFIGS_DIR}/${TARGET}.conf"
if [ ! -f "${TARGET_CONF}" ]; then
  echo "Error: Target configuration not found: ${TARGET_CONF}" >&2
  usage
fi

# Armbian only delegates to Docker for a non-root caller; as root it builds directly on the host.
if [ "${EUID}" -eq 0 ]; then
  echo "Error: run as a regular user in the docker group, not as root." >&2
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Error: the Docker daemon is not reachable (installed, running, and is ${USER:-this user} in the docker group?)." >&2
  exit 1
fi

# Ensure armbian/build is checked out at the pinned commit (an existing checkout is verified, not trusted)
if [ ! -d "${ARMBIAN_DIR}/.git" ]; then
  echo "Cloning armbian/build (${ARMBIAN_TAG})..."
  git clone --depth 1 --branch "${ARMBIAN_TAG}" https://github.com/armbian/build.git "${ARMBIAN_DIR}"
fi
if [ "$(git -C "${ARMBIAN_DIR}" rev-parse HEAD)" != "${ARMBIAN_COMMIT}" ]; then
  echo "armbian-build is not at ${ARMBIAN_TAG} (${ARMBIAN_COMMIT}); fetching it..."
  git -C "${ARMBIAN_DIR}" fetch --depth 1 origin "refs/tags/${ARMBIAN_TAG}:refs/tags/${ARMBIAN_TAG}"
  git -C "${ARMBIAN_DIR}" checkout --detach "${ARMBIAN_COMMIT}"
fi
if [ -n "$(git -C "${ARMBIAN_DIR}" status --porcelain --untracked-files=no)" ]; then
  echo "Error: armbian-build has local modifications; refusing to build from a dirty tree." >&2
  exit 1
fi

# Preset: BOARD/BRANCH/RELEASE plus an EXTRA_BUILD_ARGS array (no export needed; passed as params below)
BOARD="" BRANCH="current" RELEASE="trixie" EXTRA_BUILD_ARGS=()
# shellcheck source=/dev/null
source "${TARGET_CONF}"
if ! compgen -G "${ARMBIAN_DIR}/config/boards/${BOARD}.*" >/dev/null; then
  echo "Error: BOARD='${BOARD}' does not exist in Armbian ${ARMBIAN_TAG} (see ${ARMBIAN_DIR}/config/boards/)." >&2
  exit 1
fi

# Stage the daemon payload where customize-image.sh can read it (/tmp/overlay/nouride inside the chroot).
# Downloaded once, verified against the pinned hash, re-verified in the chroot; *.tar.gz/*.sha256 are gitignored.
PAYLOAD_DIR="${USERPATCHES_DIR}/overlay/nouride"
PAYLOAD="${PAYLOAD_DIR}/nouride-linux-arm64.tar.gz"
mkdir -p "${PAYLOAD_DIR}"
if ! echo "${NOURIDE_ARM64_SHA256}  ${PAYLOAD}" | sha256sum --check --status 2>/dev/null; then
  echo "Fetching Nouride ${NOURIDE_VERSION} (linux-arm64)..."
  curl -fL --retry 3 --connect-timeout 15 --max-time 900 -o "${PAYLOAD}.part" \
    "https://get.nouride.com/${NOURIDE_VERSION}/nouride-linux-arm64.tar.gz"
  echo "${NOURIDE_ARM64_SHA256}  ${PAYLOAD}.part" | sha256sum --check --strict
  mv "${PAYLOAD}.part" "${PAYLOAD}"
fi
echo "${NOURIDE_ARM64_SHA256}  nouride-linux-arm64.tar.gz" > "${PAYLOAD}.sha256"

# Armbian bind-mounts armbian-build/userpatches into its container; mirror ours exactly so deleted files don't linger
rm -rf "${ARMBIAN_DIR}/userpatches"
cp -a "${USERPATCHES_DIR}" "${ARMBIAN_DIR}/userpatches"

echo "======================================================================"
echo " Building Nouride OS for target: ${TARGET} (BOARD=${BOARD})"
echo " Armbian Base: ${ARMBIAN_TAG} @ ${ARMBIAN_COMMIT:0:12}"
echo "======================================================================"

cd "${ARMBIAN_DIR}"
# 'build' (not 'docker'): a non-root caller is auto-delegated into Docker and relaunched as 'build'.
# An explicit 'docker' command relaunches as 'docker' inside the container, which aborts there (exit 43).
# 'nouride' loads userpatches/config-nouride.conf; config-default.conf is never auto-loaded.
./compile.sh build nouride \
  BOARD="${BOARD}" \
  BRANCH="${BRANCH}" \
  RELEASE="${RELEASE}" \
  IMAGE_VERSION="$(git -C "${SCRIPT_DIR}" describe --tags --always --dirty 2>/dev/null || echo dev)" \
  "${EXTRA_BUILD_ARGS[@]}"

echo ""
echo "======================================================================"
echo " Build Complete!"
echo " Output images located in: ${ARMBIAN_DIR}/output/images/"
echo "======================================================================"
ls -lh "${ARMBIAN_DIR}/output/images/"* 2>/dev/null || true
