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
    echo "  -> OFFICIAL_HASH     = ${OFFICIAL_HASH}"
    [ -n "${BUILD_NUMBER:-}" ] && echo "  -> BUILD_NUMBER      = ${BUILD_NUMBER} (-> -ab${BUILD_NUMBER})"
    [ -n "${BUILD_USER:-}" ]  && echo "  -> BUILD_USER/HOST   = ${BUILD_USER}@${BUILD_HOST}"

    # ── Suppress '-dirty' in the scm version ───────────────────
    # Kleaf's stamping runs 'git status -uno --porcelain' on the kernel tree;
    # our KSU/SUSFS patches modify tracked files -> it appends '-dirty'.
    # Mark those files assume-unchanged so git reports the tree as clean.
    # (Untracked additions like fs/susfs.c are already ignored by -uno.)
    # Same method as shoey63/Kernel-Builder-GKI-Susfs.
    echo ">>> Marking modified files assume-unchanged (suppresses -dirty)..."
    git -C common ls-files -m | xargs -r git -C common update-index --assume-unchanged

    # ── Override build-user@build-host ─────────────────────────
    # _setup_env.sh hardcodes KBUILD_BUILD_USER=build-user /
    # KBUILD_BUILD_HOST=build-host (unconditionally, after fragments) and
    # ignores KLEAF_USER. Patch the file directly when overrides are set.
    if [ -n "${BUILD_USER:-}${BUILD_HOST:-}" ]; then
        SETUP_ENV="$(find build -name '_setup_env.sh' 2>/dev/null | head -1)"
        if [ -n "${SETUP_ENV}" ] && [ -f "${SETUP_ENV}" ]; then
            echo ">>> Patching ${SETUP_ENV} for KBUILD_BUILD_USER/HOST..."
            [ -n "${BUILD_USER:-}" ] && sed -i "s/KBUILD_BUILD_USER=build-user/KBUILD_BUILD_USER=${BUILD_USER}/" "${SETUP_ENV}"
            [ -n "${BUILD_HOST:-}" ] && sed -i "s/KBUILD_BUILD_HOST=build-host/KBUILD_BUILD_HOST=${BUILD_HOST}/" "${SETUP_ENV}"
        else
            echo "  [!] _setup_env.sh not found; skipping user/host override"
        fi
    fi

    # --config=stamp is REQUIRED: makes Kleaf honor SOURCE_DATE_EPOCH and embed
    # the scm version (-g<hash>) instead of '-maybe-dirty'. Defined in
    # build/kernel/kleaf/bazelrc/stamp.bazelrc (imported by common.bazelrc).
    CONFIG_FLAG="--config=stamp"

    # Build the defconfig fragment flag only if the fragment was declared.
    FRAGMENT_FLAG=""
    if grep -q 'exports_files.*custom_fragment' common/BUILD.bazel 2>/dev/null; then
        FRAGMENT_FLAG="--defconfig_fragment=//common:custom_fragment"
    else
        echo "  [!] custom_fragment not declared in common/BUILD.bazel — KSU/SUSFS configs may be missing!"
    fi

    # Kleaf's stamp pipeline reads BUILD_NUMBER to append -ab<id>. It does NOT
    # read STABLE_BUILD_VERSION / KLEAF_KERNEL_BUILD_VERSION (dead under stamp).
    # Pass via BOTH repo_env (seen by workspace_status_stamp.py -> STABLE_SCMVERSIONS)
    # and action_env (belt+suspenders).
    BUILD_NUMBER_FLAG=""
    if [ -n "${BUILD_NUMBER:-}" ]; then
        BUILD_NUMBER_FLAG="--repo_env=BUILD_NUMBER=${BUILD_NUMBER} --action_env=BUILD_NUMBER=${BUILD_NUMBER}"
    fi

    echo ">>> bazel cmdline: tools/bazel run ${CONFIG_FLAG} ${FRAGMENT_FLAG} ${BUILD_NUMBER_FLAG}"
    # shellcheck disable=SC2086
    tools/bazel run ${CONFIG_FLAG} ${FRAGMENT_FLAG} ${BUILD_NUMBER_FLAG} \
      --action_env=SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH}" \
      --action_env=KLEAF_SKIP_ABI_CHECKS=true \
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
