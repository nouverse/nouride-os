#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# Nouride OS — Armbian Overlay Build Entrypoint
# ─────────────────────────────────────────────────────────────────────────────

ARMBIAN_TAG="v26.2.1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARMBIAN_DIR="${SCRIPT_DIR}/armbian-build"
CONFIGS_DIR="${SCRIPT_DIR}/configs"
USERPATCHES_DIR="${SCRIPT_DIR}/userpatches"

function usage() {
  echo "Usage: ./build.sh <target-preset>"
  echo ""
  echo "Available presets in configs/:"
  for cfg in "${CONFIGS_DIR}"/*.conf; do
    if [ -f "${cfg}" ]; then
      basename "${cfg}" .conf | sed 's/^/  - /'
    fi
  done
  echo ""
  echo "Example:"
  echo "  ./build.sh aml-s9xx-box"
  echo "  ./build.sh orangepi-zero3"
  exit 1
}

TARGET="${1:-}"
if [ -z "${TARGET}" ]; then
  usage
fi

TARGET_CONF="${CONFIGS_DIR}/${TARGET}.conf"
if [ ! -f "${TARGET_CONF}" ]; then
  echo "Error: Target configuration not found: ${TARGET_CONF}"
  usage
fi

# Ensure Docker is available
if ! command -v docker >/dev/null 2>&1; then
  echo "Error: Docker is required to build Nouride OS."
  echo "Please install Docker and ensure the Docker daemon is running."
  exit 1
fi

echo "======================================================================"
echo " Building Nouride OS for target: ${TARGET}"
echo " Armbian Base Tag: ${ARMBIAN_TAG}"
echo "======================================================================"

# Ensure armbian/build repository is checked out at pinned tag
if [ ! -d "${ARMBIAN_DIR}/.git" ]; then
  echo "Cloning armbian/build (${ARMBIAN_TAG})..."
  git clone --depth 1 --branch "${ARMBIAN_TAG}" https://github.com/armbian/build.git "${ARMBIAN_DIR}"
else
  echo "Using existing armbian/build repository at ${ARMBIAN_DIR}"
fi

# Prepare userpatches directory inside armbian-build
mkdir -p "${ARMBIAN_DIR}/userpatches"
cp -r "${USERPATCHES_DIR}"/* "${ARMBIAN_DIR}/userpatches/"

# Source the target configuration variables
set -a
# shellcheck source=/dev/null
source "${TARGET_CONF}"
set +a

# Run Armbian Docker compilation
echo "Starting Armbian compilation in Docker..."
cd "${ARMBIAN_DIR}"

./compile.sh docker \
  BOARD="${BOARD}" \
  BRANCH="${BRANCH:-current}" \
  RELEASE="${RELEASE:-trixie}" \
  BUILD_MINIMAL="yes" \
  BUILD_DESKTOP="no" \
  KERNEL_CONFIGURE="no" \
  EXPERT="yes" \
  COMPRESS_OUTPUT="yes" \
  ${EXTRA_BUILD_ARGS:-}

echo ""
echo "======================================================================"
echo " Build Complete!"
echo " Output images located in: ${ARMBIAN_DIR}/output/images/"
echo "======================================================================"
ls -lh "${ARMBIAN_DIR}/output/images/"* 2>/dev/null || true
