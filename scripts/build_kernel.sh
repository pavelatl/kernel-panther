#!/usr/bin/env bash
set -euo pipefail

# Build kernel Image using Kleaf/Bazel (modern) or legacy Make.
# Spoofs build date and git hash via Bazel --action_env flags.

ENABLE_SUSFS="${1:-true}"

cd kernel_workspace
mkdir -p ../out out/dist

echo "=== Marking repo as clean (sanitizes custom modifications) ==="
git -C common ls-files -m | xargs -r git -C common update-index --assume-unchanged

# ── Determine build method ────────────────────────────────────
if [ -f "tools/bazel" ]; then
    echo ">>> Kleaf/Bazel build detected"

    # SOURCE_DATE_EPOCH controls the kernel's __DATE__ and timestamp
    # It's already set by the workflow via OFFICIAL_DATE from Google's git log.
    # If the user provided a custom spoof timestamp, it overrides OFFICIAL_DATE.

    echo "  -> SOURCE_DATE_EPOCH = ${SOURCE_DATE_EPOCH}"
    echo "  -> STABLE_BUILD_VERSION = -g${OFFICIAL_HASH}"
    echo "  -> KLEAF_USER = android-build"

    tools/bazel run --config=stamp \
      --action_env=SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH}" \
      --action_env=STABLE_BUILD_VERSION="-g${OFFICIAL_HASH}" \
      --action_env=KLEAF_KERNEL_BUILD_VERSION="-g${OFFICIAL_HASH}" \
      --action_env=KLEAF_SKIP_ABI_CHECKS=true \
      --action_env=KLEAF_USER=android-build \
      //common:kernel_aarch64_dist \
      -- \
      --destdir=out/dist

else
    echo ">>> Legacy Make build detected"

    mkdir -p out/dist
    export KERNEL_DIR="common"
    export BUILD_CONFIG="common/build.config.gki.aarch64"
    export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH}"
    export DIST_DIR="out/dist"
    export EXTRA_LINUX_VERSION="-g${OFFICIAL_HASH}"
    export KLEAF_USER="android-build"

    if [ -f "build/build.sh" ]; then
        bash build/build.sh
    elif [ -f "build.sh" ]; then
        bash build.sh
    else
        echo "[-] No build orchestrator found!" >&2
        exit 1
    fi
fi

# ── Verify output ──────────────────────────────────────────────
IMAGE_PATH="$(find out/dist -type f -name 'Image' | head -n1)"

if [ -z "${IMAGE_PATH}" ] || [ ! -f "${IMAGE_PATH}" ]; then
    echo "[-] No Image produced!" >&2
    exit 1
fi

cp -f "${IMAGE_PATH}" ../out/Image
echo ">>> Image: ${IMAGE_PATH}"

# ── Print kernel version string for verification ───────────────
echo ""
echo "========================================"
KERNEL_VERSION_STRING=$(strings ../out/Image | grep -E "Linux version [0-9]" | head -n1 || true)
if [ -n "$KERNEL_VERSION_STRING" ]; then
    echo "  $KERNEL_VERSION_STRING"
else
    echo "  [!] Could not read version string from Image"
fi
echo "========================================"