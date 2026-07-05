#!/usr/bin/env bash
set -euo pipefail

# Neutralizes ABI protected exports and enables KSU + SUSFS Kconfigs.
# Usage: configure_kconfigs.sh [true|false]  (enable_susfs, default: true)

ENABLE_SUSFS="${1:-true}"

cd kernel_workspace

echo "=== Configuring Kconfigs ==="

# ── Neutralize ABI protected exports ──────────────────────────
echo ">>> Neutralizing ABI protected exports..."
for f in common/android/abi_gki_protected_exports*; do
    [ -f "$f" ] && > "$f"
done

# ── Detect build system ──────────────────────────────────────
cd common

if [ -f "BUILD.bazel" ]; then
    echo ">>> Bazel detected: injecting post_defconfig_fragments..."

    cat > custom_fragment << FRAGEOF
# ── KernelSU-Next ──
CONFIG_KSU=y

FRAGEOF

    if [ "${ENABLE_SUSFS}" = "true" ]; then
        cat >> custom_fragment << 'FRAGEOF'
# ── SUSFS ──
CONFIG_SUSFS=y
CONFIG_SUSFS_SUS_PATH=y
CONFIG_SUSFS_SUS_MOUNT=y
CONFIG_SUSFS_TRY_UMOUNT=y
CONFIG_SUSFS_SPOOF_UNLINK=y
CONFIG_SUSFS_SUS_KSTAT=y
CONFIG_SUSFS_SUS_OPEN=y
CONFIG_SUSFS_SUS_INOTIFY=y
CONFIG_SUSFS_SUS_GETDENTS=y
CONFIG_SUSFS_SUS_GETDENTS64=y
CONFIG_SUSFS_SUS_IOCTL=y
CONFIG_SUSFS_SUS_PATH_PARSE=y
CONFIG_SUSFS_SUS_MOUNT_PARSE=y
CONFIG_SUSFS_SPOOF_STATFS=y
CONFIG_SUSFS_SPOOF_ACCESS=y
CONFIG_SUSFS_ENABLE_LOG=y
FRAGEOF
    fi

    echo 'exports_files(["custom_fragment"])' >> BUILD.bazel
    sed -i '/name = "kernel_aarch64",/a \    post_defconfig_fragments = ["custom_fragment"],' BUILD.bazel
    echo "custom_fragment" >> .git/info/exclude

else
    echo ">>> Legacy Make detected: creating fragment file..."
    cat > "arch/arm64/configs/custom.fragment" << FRAGEOF
# ── KernelSU-Next ──
CONFIG_KSU=y
FRAGEOF

    if [ "${ENABLE_SUSFS}" = "true" ]; then
        cat >> "arch/arm64/configs/custom.fragment" << 'FRAGEOF'
# ── SUSFS ──
CONFIG_SUSFS=y
CONFIG_SUSFS_SUS_PATH=y
CONFIG_SUSFS_SUS_MOUNT=y
CONFIG_SUSFS_TRY_UMOUNT=y
CONFIG_SUSFS_SPOOF_UNLINK=y
CONFIG_SUSFS_SUS_KSTAT=y
CONFIG_SUSFS_SUS_OPEN=y
CONFIG_SUSFS_SUS_INOTIFY=y
CONFIG_SUSFS_SUS_GETDENTS=y
CONFIG_SUSFS_SUS_GETDENTS64=y
CONFIG_SUSFS_SUS_IOCTL=y
CONFIG_SUSFS_SUS_PATH_PARSE=y
CONFIG_SUSFS_SUS_MOUNT_PARSE=y
CONFIG_SUSFS_SPOOF_STATFS=y
CONFIG_SUSFS_SPOOF_ACCESS=y
CONFIG_SUSFS_ENABLE_LOG=y
FRAGEOF
    fi

    # For legacy builds, export the fragment path
    export EXTRA_DEFCONFIG_FRAGMENTS="arch/arm64/configs/custom.fragment"
fi

cd ..
echo ">>> Kconfig configuration complete"