#!/usr/bin/env bash
set -euo pipefail

cd kernel_workspace

echo ">>> Fixing SUSFS patch rejections..."

# Helper: insert line after a pattern
insert_after() {
    local file="$1" pattern="$2" line="$3"
    if ! grep -qF "$line" "$file"; then
        sed -i "/${pattern}/a\\${line}" "$file"
    fi
}

# ── 1. fs/exec.c ────────────────────────────────────────────
if [ -f "common/fs/exec.c.rej" ]; then
    echo ">>> Fixing exec.c.rej..."
    insert_after "common/fs/exec.c" "linux/uaccess.h" "#ifdef CONFIG_KSU_SUSFS"
    insert_after "common/fs/exec.c" "CONFIG_KSU_SUSFS" "#include <linux/susfs_def.h>"
    insert_after "common/fs/exec.c" "susfs_def.h" "#endif"
    grep -q 'susfs_def.h' common/fs/exec.c && echo "  -> exec.c ✓" && rm -f common/fs/exec.c.rej
fi

# ── 2. fs/proc/base.c ──────────────────────────────────────
if [ -f "common/fs/proc/base.c.rej" ]; then
    echo ">>> Fixing base.c.rej..."
    insert_after "common/fs/proc/base.c" 'internal.h' '#if defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)'
    insert_after "common/fs/proc/base.c" "CONFIG_KSU_SUSFS_OPEN_REDIRECT" "#include <linux/susfs_def.h>"
    insert_after "common/fs/proc/base.c" "susfs_def.h" "#endif"
    grep -q 'susfs_def.h' common/fs/proc/base.c && echo "  -> base.c ✓" && rm -f common/fs/proc/base.c.rej
fi

# ── 3. fs/namespace.c ──────────────────────────────────────
if [ -f "common/fs/namespace.c.rej" ]; then
    echo ">>> Fixing namespace.c.rej..."
    insert_after "common/fs/namespace.c" 'pnode.h' "#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT"
    insert_after "common/fs/namespace.c" "CONFIG_KSU_SUSFS_SUS_MOUNT" "#include <linux/susfs_def.h>"
    insert_after "common/fs/namespace.c" "susfs_def.h" "#endif"

    if grep -q "trace/hooks/blk.h" common/fs/namespace.c; then
        ANCHOR="trace/hooks/blk.h"
    elif grep -q "linux/nsproxy.h" common/fs/namespace.c; then
        ANCHOR="linux/nsproxy.h"
    else
        ANCHOR="linux/mount.h"
    fi

    insert_after "common/fs/namespace.c" "$ANCHOR" "#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT"
    insert_after "common/fs/namespace.c" "CONFIG_KSU_SUSFS_SUS_MOUNT" "extern bool susfs_is_current_ksu_domain(void);"
    insert_after "common/fs/namespace.c" "susfs_is_current_ksu_domain" "extern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;"
    insert_after "common/fs/namespace.c" "not_decrypted;" "#define CL_COPY_MNT_NS BIT(25)"
    insert_after "common/fs/namespace.c" "CL_COPY_MNT_NS" "#endif"

    grep -q 'susfs_is_current_ksu_domain' common/fs/namespace.c && echo "  -> namespace.c ✓" && rm -f common/fs/namespace.c.rej
fi

# ── 4. fs/proc/task_mmu.c (skip on 6.1) ────────────────────
if [ -f "common/fs/proc/task_mmu.c.rej" ]; then
    echo ">>> Skipping task_mmu.c.rej (not needed on 6.1)"
    rm -f common/fs/proc/task_mmu.c.rej
fi

# ── 5. fs/open.c ────────────────────────────────────────────
if [ -f "common/fs/open.c.rej" ]; then
    echo ">>> Fixing open.c.rej..."
    insert_after "common/fs/open.c" "linux/mount.h" "#ifdef CONFIG_KSU_SUSFS"
    insert_after "common/fs/open.c" "CONFIG_KSU_SUSFS" "#include <linux/susfs_def.h>"
    insert_after "common/fs/open.c" "susfs_def.h" "#endif"
    rm -f common/fs/open.c.rej
    echo "  -> open.c ✓"
fi

# ── 6. fs/namei.c ───────────────────────────────────────────
if [ -f "common/fs/namei.c.rej" ]; then
    echo ">>> Skipping namei.c.rej"
    rm -f common/fs/namei.c.rej
fi

# ── Final check ─────────────────────────────────────────────
REMAINING=$(find common -type f -name '*.rej' 2>/dev/null || true)
if [ -n "${REMAINING}" ]; then
    echo "[-] Unresolved rejections:" >&2
    echo "${REMAINING}" >&2
    echo ">>> Continuing (build may fail)" >&2
else
    echo ">>> All patch rejections resolved!"
fi
