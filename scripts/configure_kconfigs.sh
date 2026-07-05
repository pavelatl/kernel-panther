#!/usr/bin/env bash
set -euo pipefail

# Builds the custom defconfig fragment (KSU + SUSFS) and exports it as a
# Bazel label for Kleaf. The fragment is consumed at build time via:
#     tools/bazel run //common:kernel_aarch64_dist \
#         --defconfig_fragment=//common:custom_fragment
#
# NOTE: We intentionally do NOT sed-edit common/BUILD.bazel to inject
# `post_defconfig_fragments`. On android14-6.1-lts the kernel_aarch64
# target is created by the define_common_kernels() macro and the
# `post_defconfig_fragments` attribute does not exist there — such a sed
# is a silent no-op. The --defconfig_fragment flag is the canonical way.
#
# Usage: configure_kconfigs.sh [true|false]  (enable_susfs, default: true)

ENABLE_SUSFS="${1:-true}"

cd kernel_workspace

echo "=== Configuring Kconfigs ==="

# ── Neutralize ABI protected exports ──────────────────────────
echo ">>> Neutralizing ABI protected exports..."
for f in common/android/abi_gki_protected_exports*; do
    [ -f "$f" ] && > "$f"
done

cd common

# build_fragment: emits the defconfig fragment consumed by Kleaf via
# --defconfig_fragment=//common:custom_fragment.
#
# IMPORTANT: keep CONFIG_* tokens OUT OF COMMENTS inside the heredoc below.
# Kleaf's fragment validator does substring matching on the symbol name and
# will fold any comment line containing a symbol name into that symbol's
# "expected" value, breaking the build. Explanatory notes live here, in a
# shell comment (outside the heredoc), where the validator never looks.
#
# NOTE on SUSFS naming: pershoot/KernelSU-Next dev-susfs declares the SUSFS
# bridge under the KSU-prefixed namespace (master + 9 sub-features). The
# unprefixed legacy names from sidex15/susfs4ksu DO NOT EXIST in pershoot's
# fork — do not add them. Verified against kernel/Kconfig on dev-susfs and
# the 50_*_AOSP.patch (#ifdef usage).
build_fragment() {
    cat <<'FRAG'
# ── KernelSU-Next ──
CONFIG_KSU=y
FRAG

    if [ "${ENABLE_SUSFS}" = "true" ]; then
        cat <<'FRAG'
# ── SUSFS bridge (pershoot/KernelSU-Next dev-susfs) ──
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
FRAG
    fi
}

if [ -f "BUILD.bazel" ]; then
    echo ">>> Bazel detected: writing custom_fragment + exports_files..."
    build_fragment > custom_fragment
    if ! grep -q 'exports_files(\["custom_fragment"\])' BUILD.bazel 2>/dev/null; then
        echo 'exports_files(["custom_fragment"])' >> BUILD.bazel
    fi
    # Keep the workspace clean-ish for any git-based sanity checks.
    grep -qx 'custom_fragment' .git/info/exclude 2>/dev/null \
        || echo "custom_fragment" >> .git/info/exclude 2>/dev/null || true
else
    echo ">>> Legacy Make detected: writing arch/arm64/configs/custom.fragment..."
    build_fragment > "arch/arm64/configs/custom.fragment"
    export EXTRA_DEFCONFIG_FRAGMENTS="arch/arm64/configs/custom.fragment"
fi

cd ..
echo ">>> Kconfig configuration complete"
echo ">>> Fragment label (Bazel): //common:custom_fragment"
