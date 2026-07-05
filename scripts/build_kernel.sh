#!/usr/bin/env bash
set -euo pipefail

# Build kernel Image using Kleaf/Bazel (modern) or legacy Make.
# Spoofs build date and git hash via Bazel --action_env flags.
#
# The custom defconfig fragment (//common:custom_fragment) is injected via
# the canonical Kleaf --defconfig_fragment flag, configured in
# configure_kconfigs.sh.

cd kernel_workspace
mkdir -p ../out out/dist

# ── Determine build method ────────────────────────────────────
if [ -f "tools/bazel" ]; then
    echo ">>> Kleaf/Bazel build detected"

    echo "  -> SOURCE_DATE_EPOCH = ${SOURCE_DATE_EPOCH}"
    echo "  -> STABLE_BUILD_VERSION = -g${OFFICIAL_HASH}"
    echo "  -> KLEAF_USER = android-build"

    # --config=stamp only exists if declared in a .bazelrc; detect to avoid
    # a hard failure on trees where it is absent.
    CONFIG_FLAG=""
    if grep -rq 'stamp' .bazelrc build/kernel/kleaf/.bazelrc 2>/dev/null; then
        CONFIG_FLAG="--config=stamp"
    fi

    # Build the defconfig fragment flag only if the fragment was declared.
    FRAGMENT_FLAG=""
    if grep -q 'exports_files.*custom_fragment' common/BUILD.bazel 2>/dev/null; then
        FRAGMENT_FLAG="--defconfig_fragment=//common:custom_fragment"
    else
        echo "  [!] custom_fragment not declared in common/BUILD.bazel — KSU/SUSFS configs may be missing!"
    fi

    # shellcheck disable=SC2086
    tools/bazel run ${CONFIG_FLAG} ${FRAGMENT_FLAG} \
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
KERNEL_VERSION_STRING="$(strings ../out/Image | grep -E "Linux version [0-9]" | head -n1 || true)"
if [ -n "$KERNEL_VERSION_STRING" ]; then
    echo "  $KERNEL_VERSION_STRING"
else
    echo "  [!] Could not read version string from Image"
fi
echo "========================================"
