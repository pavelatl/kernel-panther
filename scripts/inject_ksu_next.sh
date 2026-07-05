#!/usr/bin/env bash
set -euo pipefail

# Integrates pershoot/KernelSU-Next into the GKI kernel source tree.
# This fork includes pre-applied SUSFS hooks.
# Uses the "Gatekeeper" approach (GNU Make overrides) to bypass the
# Kleaf/Bazel sandbox and feed correct versioning math to the compiler.

KSU_TAG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag) KSU_TAG="$2"; shift 2 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

cd kernel_workspace
WORKSPACE_DIR="$(pwd)"
[ -d common ] || { echo "[-] common/ not found"; exit 1; }

KSU_OWNER="pershoot"
KSU_REPO="KernelSU-Next"
KSU_DIR="KernelSU-Next"
UPSTREAM_REPO="KernelSU-Next/KernelSU-Next"
UPSTREAM_BRANCH="dev"

echo "=== Integrating ${KSU_OWNER}/${KSU_REPO} ==="

# ── Clone ───────────────────────────────────────────────────────
rm -rf "${KSU_DIR}"
echo ">>> Cloning ${KSU_OWNER}/${KSU_REPO}..."
git clone "https://github.com/${KSU_OWNER}/${KSU_REPO}.git" "${KSU_DIR}"

cd "${KSU_DIR}"

# Checkout specific tag or latest release
if [ -n "${KSU_TAG}" ]; then
    git checkout "${KSU_TAG}" 2>/dev/null || {
        echo "[-] Tag ${KSU_TAG} not found, using latest release"
        git checkout "$(git describe --abbrev=0 --tags)" 2>/dev/null || true
    }
else
    LATEST_TAG="$(git describe --abbrev=0 --tags 2>/dev/null || echo '')"
    if [ -n "${LATEST_TAG}" ]; then
        git checkout "${LATEST_TAG}"
        echo ">>> Checked out: ${LATEST_TAG}"
    fi
fi

# ── Symlink + manual integration (no setup.sh) ─────────────────
cd "${WORKSPACE_DIR}"

DRIVER_ROOT="common/drivers"
rm -rf "${DRIVER_ROOT}/kernelsu"
ln -sfn "../../${KSU_DIR}/kernel" "${DRIVER_ROOT}/kernelsu"
[ -L "${DRIVER_ROOT}/kernelsu" ] || { echo "[-] Symlink failed"; exit 1; }
echo ">>> Symlink: ${DRIVER_ROOT}/kernelsu → ../../${KSU_DIR}/kernel"

echo ">>> Patching drivers/Makefile..."
if ! grep -q "kernelsu" "${DRIVER_ROOT}/Makefile" 2>/dev/null; then
    echo 'obj-$(CONFIG_KSU)	+= kernelsu/' >> "${DRIVER_ROOT}/Makefile"
fi

echo ">>> Patching drivers/Kconfig..."
if ! grep -q "kernelsu/Kconfig" "${DRIVER_ROOT}/Kconfig" 2>/dev/null; then
    echo 'source "drivers/kernelsu/Kconfig"' >> "${DRIVER_ROOT}/Kconfig"
fi

# ── Find upstream sync point for version parity ──────────────────
echo ">>> Locating upstream sync point..."
git -C "${KSU_DIR}" fetch --quiet "https://github.com/${UPSTREAM_REPO}.git" "${UPSTREAM_BRANCH}" 2>/dev/null || true

UPSTREAM_HASH=$(git -C "${KSU_DIR}" merge-base HEAD FETCH_HEAD 2>/dev/null || echo "")
SHORT_HASH="${UPSTREAM_HASH:0:7}"
CALCULATED_COUNT=$(git -C "${KSU_DIR}" rev-list --count "${UPSTREAM_HASH}" 2>/dev/null || echo "0")
CALCULATED_TAG=$(git -C "${KSU_DIR}" describe --tags --abbrev=0 "${UPSTREAM_HASH}" 2>/dev/null || echo "v0.0.0")

echo "  -> Upstream hash:  ${SHORT_HASH}"
echo "  -> Upstream count: ${CALCULATED_COUNT}"
echo "  -> Upstream tag:   ${CALCULATED_TAG}"

# ── Gatekeeper: Bazel sandbox bypass ─────────────────────────────
TARGET_KBUILD="${WORKSPACE_DIR}/${KSU_DIR}/kernel/Kbuild"

if [ -f "$TARGET_KBUILD" ]; then
    {
        echo "override KSU_GIT_VERSION_VALID := 1"
        echo "override KSU_GIT_VERSION := ${CALCULATED_COUNT}"
        echo "override KSU_GIT_TAG := ${CALCULATED_TAG}"
        echo "override KSU_COMMIT_SHA := ${SHORT_HASH}"
        echo "override KSU_GIT_BRANCH := ${UPSTREAM_BRANCH}"
        echo "override KSU_LOCAL_VERSION := ${CALCULATED_COUNT}"
        echo "override KSU_TAG_NAME := ${CALCULATED_TAG}"
        echo "override KSU_BRANCH_NAME := ${UPSTREAM_BRANCH}"
        echo "override KSU_BRANCH := ${UPSTREAM_BRANCH}"
        cat "$TARGET_KBUILD"
    } > "${TARGET_KBUILD}.tmp" && mv "${TARGET_KBUILD}.tmp" "$TARGET_KBUILD"
    echo ">>> Gatekeeper overrides injected into Kbuild"
fi

echo ">>> ${KSU_OWNER}/${KSU_REPO} integrated!"
