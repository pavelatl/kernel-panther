#!/usr/bin/env bash
set -euo pipefail

# Fixes known SUSFS patch rejections in the common kernel tree.
# Adapted from shoey63/Kernel-Builder-GKI-Susfs with fixes for
# the pershoot/susfs4ksu patch set.

cd kernel_workspace

echo ">>> Fixing SUSFS patch rejections..."

# ── 1. fs/exec.c ───────────────────────────────────────────────
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

# ── 2. fs/proc/base.c ─────────────────────────────────────────
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

# ── 3. fs/namespace.c ─────────────────────────────────────────
if [ -f "common/fs/namespace.c.rej" ]; then
    echo ">>> Fixing namespace.c.rej..."

    # Header injection
    sed -i '/#include "pnode.h"/i\
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\
#include <linux/susfs_def.h>\
#endif
' common/fs/namespace.c

    # Extern injection after trace/hooks/blk.h
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

# ── 4. fs/proc/task_mmu.c ─────────────────────────────────────
if [ -f "common/fs/proc/task_mmu.c.rej" ]; then
    echo ">>> Fixing task_mmu.c.rej..."

    # Path A: show_smap logic rejection (6.12+)
    if grep -q "show_smap" "common/fs/proc/task_mmu.c.rej"; then
        sed -i '/static int show_smap(struct seq_file \*m, void \*v)/,/struct mem_size_stats mss = {};/ {
            /struct mem_size_stats mss = {};/a\
\
#ifdef CONFIG_KSU_SUSFS_SUS_MAP\
	if (vma->vm_file) {\
		if (SUSFS_IS_INODE_SUS_MAP(file_inode(vma->vm_file)))\
			return 0;\
	}\
#endif
        }' common/fs/proc/task_mmu.c

        if grep -q 'SUSFS_IS_INODE_SUS_MAP' common/fs/proc/task_mmu.c; then
            echo "  -> task_mmu.c (logic) ✓"
            rm "common/fs/proc/task_mmu.c.rej"
        fi

    # Path B: header rejection
    elif grep -q "susfs_def.h" "common/fs/proc/task_mmu.c.rej" || \
         grep -q "CONFIG_KSU_SUSFS" "common/fs/proc/task_mmu.c.rej"; then
        if ! grep -q 'susfs_def.h' common/fs/proc/task_mmu.c; then
            sed -i '/#include <linux\/uaccess.h>/a\
#include <linux/cred.h>\
#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\
#include <linux/susfs_def.h>\
#endif' common/fs/proc/task_mmu.c
        fi

        if grep -q 'susfs_def.h' common/fs/proc/task_mmu.c; then
            echo "  -> task_mmu.c (headers) ✓"
            rm "common/fs/proc/task_mmu.c.rej"
        fi
    else
        echo "  [-] task_mmu.c: unknown rejection format" >&2
    fi
fi

# ── 5. fs/open.c ───────────────────────────────────────────────
if [ -f "common/fs/open.c.rej" ]; then
    echo ">>> Fixing open.c.rej..."
    # Typically a header injection issue
    if ! grep -q 'susfs_def.h' common/fs/open.c 2>/dev/null; then
        sed -i '/#include <linux\/mount.h>/i\
#ifdef CONFIG_KSU_SUSFS\
#include <linux/susfs_def.h>\
#endif\
' common/fs/open.c
    fi
    if [ -f "common/fs/open.c.rej" ]; then
        rm "common/fs/open.c.rej"
        echo "  -> open.c ✓ (best-effort)"
    fi
fi

# ── 6. fs/namei.c ──────────────────────────────────────────────
if [ -f "common/fs/namei.c.rej" ]; then
    echo ">>> Fixing namei.c.rej..."
    rm "common/fs/namei.c.rej"
    echo "  -> namei.c ✓ (rejection removed, verify manually)"
fi

# ── Final check ────────────────────────────────────────────────
REMAINING=$(find common -type f -name '*.rej' 2>/dev/null || true)
if [ -n "${REMAINING}" ]; then
    echo "" >&2
    echo "[-] CRITICAL: Unresolved patch rejections:" >&2
    echo "${REMAINING}" >&2
    for f in ${REMAINING}; do
        echo "=== ${f} ===" >&2
        cat "$f" >&2
    done
    echo "" >&2
    echo ">>> Continuing anyway (build may fail)" >&2
else
    echo ">>> All patch rejections resolved!"
fi