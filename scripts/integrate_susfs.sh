#!/usr/bin/env bash
set -euo pipefail

# Integrates SUSFS kernel-only patches from pershoot/susfs4ksu.
# IMPORTANT: Only the kernel patches are applied. The KSU patch is
# SKIPPED because pershoot/KernelSU-Next already has SUSFS hooks.
#
# Branch: aosp-android14-6.1-dev

cd kernel_workspace
[ -d common ] || { echo "[-] common/ not found"; exit 1; }

SUSFS_OWNER="pershoot"
SUSFS_REPO="susfs4ksu"
SUSFS_BRANCH="aosp-android14-6.1-dev"

echo "=== Integrating SUSFS (${SUSFS_OWNER}/${SUSFS_REPO}) ==="
echo ">>> Branch: ${SUSFS_BRANCH}"
echo ">>> NOTE: Only kernel patches. KSU patch SKIPPED (pre-applied in pershoot/KernelSU-Next)"

# ── Clone ───────────────────────────────────────────────────────
echo ">>> Cloning susfs4ksu..."
rm -rf susfs4ksu
git clone --depth=1 -b "${SUSFS_BRANCH}" \
    "https://gitlab.com/${SUSFS_OWNER}/${SUSFS_REPO}.git" susfs4ksu

PATCHES_DIR="susfs4ksu/kernel_patches"

# ── Copy kernel source files ────────────────────────────────────
echo ">>> Copying fs/ files into common/..."
cp -rf "${PATCHES_DIR}/fs/"* common/fs/ 2>/dev/null || true

echo ">>> Copying include/linux/ files into common/..."
cp -rf "${PATCHES_DIR}/include/linux/"* common/include/linux/ 2>/dev/null || true

# ── Find and apply the AOSP kernel patch ────────────────────────
AOSP_PATCH=""
for candidate in \
    "${PATCHES_DIR}/50_add_susfs_in_gki-android14-6.1_AOSP.patch" \
    "${PATCHES_DIR}/50_add_susfs_in_aosp-android14-6.1.patch" \
    "${PATCHES_DIR}/50_add_susfs_in_android14-6.1.patch"; do
    if [ -f "$candidate" ]; then
        AOSP_PATCH="$candidate"
        break
    fi
done

if [ -n "${AOSP_PATCH}" ]; then
    echo ">>> Found kernel patch: $(basename "${AOSP_PATCH}")"
    cp "${AOSP_PATCH}" common/
    (cd common && patch -p1 --no-backup-if-mismatch < "$(basename "${AOSP_PATCH}")") || true
    rm -f "common/$(basename "${AOSP_PATCH}")"
    echo ">>> Kernel SUSFS patch applied"
else
    echo "[-] No AOSP kernel patch found!"
    echo "    Available patches in kernel_patches/:"
    ls "${PATCHES_DIR}"/*.patch 2>/dev/null || echo "    (none)"
    exit 1
fi

# ── Apply modules/mmio tracepoints patch (if present) ──────────
MODULES_PATCH="${PATCHES_DIR}/60_modules_no-mmio_tracepoints.patch"
if [ -f "${MODULES_PATCH}" ]; then
    echo ">>> Applying modules tracepoints patch..."
    cp "${MODULES_PATCH}" common/
    (cd common && patch -p1 --no-backup-if-mismatch < "$(basename "${MODULES_PATCH}")") || true
    rm -f "common/$(basename "${MODULES_PATCH}")"
fi

# ── DO NOT apply the KSU/SUSFS bridge patch ────────────────────
# The patch at kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch
# is NOT applied because pershoot/KernelSU-Next already contains
# the SUSFS integration hooks.

echo ""
echo ">>> SUSFS common-side integration complete!"
echo ">>> KSU-side patch intentionally SKIPPED"