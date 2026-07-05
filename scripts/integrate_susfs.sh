#!/usr/bin/env bash
set -euo pipefail

# Integrates SUSFS kernel-only patches from pershoot/susfs4ksu.
#
# Method (per pershoot/susfs4ksu README — HYBRID):
#   1. cp kernel_patches/fs/susfs.c        → common/fs/        (new file)
#   2. cp kernel_patches/include/linux/*   → common/include/linux/  (susfs.h, susfs_def.h)
#   3. patch -p1 < 50_add_susfs_in_gki-android14-6.1_AOSP.patch   (in common/)
#   4. patch -p1 < 60_modules_no-mmio_tracepoints.patch           (optional)
#
# The KSU-side patch kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch
# is intentionally SKIPPED: inject_ksu_next.sh checks out the `dev-susfs`
# branch of pershoot/KernelSU-Next, which already defines CONFIG_KSU_SUSFS*
# and the inline hooks. Applying 10_ on top would conflict.
#
# Branch: aosp-android14-6.1-dev

cd kernel_workspace
[ -d common ] || { echo "[-] common/ not found"; exit 1; }

SUSFS_OWNER="pershoot"
SUSFS_REPO="susfs4ksu"
SUSFS_BRANCH="aosp-android14-6.1-dev"

echo "=== Integrating SUSFS (${SUSFS_OWNER}/${SUSFS_REPO}) ==="
echo ">>> Branch: ${SUSFS_BRANCH}"
echo ">>> NOTE: KSU bridge patch SKIPPED (dev-susfs provides CONFIG_KSU_SUSFS)."

# ── Clone ───────────────────────────────────────────────────────
echo ">>> Cloning susfs4ksu..."
rm -rf susfs4ksu
git clone --depth=1 -b "${SUSFS_BRANCH}" \
    "https://gitlab.com/${SUSFS_OWNER}/${SUSFS_REPO}.git" susfs4ksu

PATCHES_DIR="susfs4ksu/kernel_patches"

# ── Copy new kernel source files ────────────────────────────────
# kernel_patches/fs/ contains ONLY susfs.c (a brand-new file). It does NOT
# contain full copies of exec.c/open.c/etc — those are modified via the patch.
echo ">>> Copying fs/susfs.c into common/fs/..."
cp -rf "${PATCHES_DIR}/fs/"* common/fs/

echo ">>> Copying include/linux/{susfs.h,susfs_def.h} into common/include/linux/..."
cp -rf "${PATCHES_DIR}/include/linux/"* common/include/linux/

# ── helper: apply a patch allowing rejections ──────────────────
apply_patch() {
    local patch_name="$1"
    local patch_src="${PATCHES_DIR}/${patch_name}"
    [ -f "${patch_src}" ] || { echo "[-] Patch not found: ${patch_src}"; return 1; }

    cp "${patch_src}" "common/${patch_name}"
    set +e
    ( cd common && patch -p1 --no-backup-if-mismatch --fuzz=3 < "${patch_name}" )
    local rc=$?
    set -e
    rm -f "common/${patch_name}"

    if [ "${rc}" -eq 0 ]; then
        echo ">>> ${patch_name} applied cleanly"
    elif [ "${rc}" -eq 1 ]; then
        echo ">>> ${patch_name} applied with rejections (fix_susfs_rejections.sh will clean up)"
    else
        echo "[-] ${patch_name} failed to apply (rc=${rc})"
        return "${rc}"
    fi
    return 0
}

# ── Find and apply the AOSP kernel patch ────────────────────────
AOSP_PATCH=""
for candidate in \
    "50_add_susfs_in_gki-android14-6.1_AOSP.patch" \
    "50_add_susfs_in_aosp-android14-6.1.patch" \
    "50_add_susfs_in_android14-6.1.patch"; do
    if [ -f "${PATCHES_DIR}/${candidate}" ]; then
        AOSP_PATCH="${candidate}"
        break
    fi
done

if [ -z "${AOSP_PATCH}" ]; then
    echo "[-] No AOSP kernel patch found in ${PATCHES_DIR}/"
    ls "${PATCHES_DIR}"/*.patch 2>/dev/null || echo "    (no .patch files)"
    exit 1
fi

apply_patch "${AOSP_PATCH}"

# ── Apply modules/mmio tracepoints patch (if present) ──────────
MODULES_PATCH="60_modules_no-mmio_tracepoints.patch"
if [ -f "${PATCHES_DIR}/${MODULES_PATCH}" ]; then
    apply_patch "${MODULES_PATCH}"
fi

echo ""
echo ">>> SUSFS kernel-side integration complete."
echo ">>> Run fix_susfs_rejections.sh next to clean up any .rej files."
