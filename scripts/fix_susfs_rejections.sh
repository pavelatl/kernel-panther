#!/usr/bin/env bash
set -euo pipefail

cd kernel_workspace

echo ">>> Fixing SUSFS patch rejections..."

# ── 1. fs/exec.c ────────────────────────────────────────────
if [ -f "common/fs/exec.c.rej" ]; then
    echo ">>> Fixing exec.c.rej..."
    sed -i '/#include <linux\/uaccess.h>/i\
#ifdef CONFIG_KSU_SUSFS\
#include <linux/susfs_def.h>\
#endif\
' common/fs/exec.c
    if grep -q 'susfs_def.h' common/fs/exec.c; then
        echo "  -> exec.c ✓"
        rm "common/fs/exec.c.rej"
    else
        echo "  [-] exec.c fix failed" >&2
    fi
fi

# ── 2. fs/proc/base.c ──────────────────────────────────────
if [ -f "common/fs/proc/base.c.rej" ]; then
    echo ">>> Fixing base.c.rej..."
    sed -i '/#include "internal.h"/i\
#if defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\
#include <linux/susfs_def.h>\
#endif\
' common/fs/proc/base.c
    if grep -q 'susfs_def.h' common/fs/proc/base.c; then
        echo "  -> base.c ✓"
        rm "common/fs/proc/base.c.rej"
    else
        echo "  [-] base.c fix failed" >&2
    fi
fi

# ── 3. fs/namespace.c ──────────────────────────────────────
if [ -f "common/fs/namespace.c.rej" ]; then
    echo ">>> Fixing namespace.c.rej..."

    sed -i '/#include "pnode.h"/i\
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\
#include <linux/susfs_def.h>\
#endif
' common/fs/namespace.c

    if grep -q "trace/hooks/blk.h" common/fs/namespace.c; then
        ANCHOR="trace/hooks/blk.h"
    elif grep -q "linux/nsproxy.h" common/fs/namespace.c; then
        ANCHOR="linux/nsproxy.h"
    else
        ANCHOR="linux/mount.h"
    fi

    sed -i "/#include <${ANCHOR}>/a\
\
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\
extern bool susfs_is_current_ksu_domain(void);\
extern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;\
#define CL_COPY_MNT_NS BIT(25)\
#endif
' common/fs/namespace.c

    if grep -q 'susfs_is_current_ksu_domain' common/fs/namespace.c; then
        echo "  -> namespace.c ✓"
        rm "common/fs/namespace.c.rej"
    else
        echo "  [-] namespace.c fix failed" >&2
    fi
fi

# ── 4. fs/proc/task_mmu.c (skip on 6.1) ────────────────────
if [ -f "common/fs/proc/task_mmu.c.rej" ]; then
    echo ">>> Skipping task_mmu.c.rej (not needed on 6.1)"
    rm -f common/fs/proc/task_mmu.c.rej
fi

# ── 5. fs/open.c ────────────────────────────────────────────
if [ -f "common/fs/open.c.rej" ]; then
    echo ">>> Fixing open.c.rej..."
    sed -i '/#include <linux\/mount.h>/i\
#ifdef CONFIG_KSU_SUSFS\
#include <linux/susfs_def.h>\
#endif\
' common/fs/open.c
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
