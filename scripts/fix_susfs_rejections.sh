#!/usr/bin/env bash
set -euo pipefail

# Cleans up known .rej files left by the SUSFS 50_*_AOSP.patch when the
# kernel tree context has drifted from the patch's baseline.
#
# Each fix is IDEMPOTENT: it only inserts if the block is missing. This
# prevents the duplicate-#if corruption seen in run #4, where the patch
# partially applied and this script re-inserted a second block, leaving
# fs/proc/base.c with an unterminated #if.
#
# All multi-line inserts use awk (no shell/sed quote hell).

cd kernel_workspace

echo ">>> Fixing SUSFS patch rejections..."

TMP_BLOCK="$(mktemp)"
trap 'rm -f "${TMP_BLOCK}"' EXIT

# insert_before <file> <anchor_regex> <block_file>
insert_before() {
    local file="$1" anchor="$2" block="$3"
    awk -v anchor="$anchor" '
        FNR == NR { block = block $0 "\n"; next }
        { if (!done && $0 ~ anchor) { printf "%s", block; done=1 } print }
    ' "$block" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# insert_after <file> <anchor_regex> <block_file>
insert_after() {
    local file="$1" anchor="$2" block="$3"
    awk -v anchor="$anchor" '
        FNR == NR { block = block $0 "\n"; next }
        { print }
        { if (!done && $0 ~ anchor) { printf "%s", block; done=1 } }
    ' "$block" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# ── 1. fs/exec.c — add susfs_def.h include ────────────────────
if [ -f "common/fs/exec.c.rej" ]; then
    echo ">>> Fixing exec.c.rej..."
    if ! grep -q 'susfs_def.h' common/fs/exec.c; then
        cat > "${TMP_BLOCK}" <<'BLK'
#ifdef CONFIG_KSU_SUSFS
#include <linux/susfs_def.h>
#endif
BLK
        insert_before common/fs/exec.c '#include <linux/uaccess.h>' "${TMP_BLOCK}"
    fi
    if grep -q 'susfs_def.h' common/fs/exec.c; then
        echo "  -> exec.c OK"; rm -f common/fs/exec.c.rej
    else
        echo "  [-] exec.c fix failed" >&2
    fi
fi

# ── 2. fs/proc/base.c — add susfs_def.h include ──────────────
if [ -f "common/fs/proc/base.c.rej" ]; then
    echo ">>> Fixing base.c.rej..."
    if ! grep -q 'susfs_def.h' common/fs/proc/base.c; then
        cat > "${TMP_BLOCK}" <<'BLK'
#if defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)
#include <linux/susfs_def.h>
#endif
BLK
        insert_before common/fs/proc/base.c '#include "internal.h"' "${TMP_BLOCK}"
    fi
    if grep -q 'susfs_def.h' common/fs/proc/base.c; then
        echo "  -> base.c OK"; rm -f common/fs/proc/base.c.rej
    else
        echo "  [-] base.c fix failed" >&2
    fi
fi

# ── 3. fs/namespace.c — include + extern declarations ────────
if [ -f "common/fs/namespace.c.rej" ]; then
    echo ">>> Fixing namespace.c.rej..."

    # 3a. include block before pnode.h
    if ! grep -q 'susfs_def.h' common/fs/namespace.c; then
        cat > "${TMP_BLOCK}" <<'BLK'
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
#include <linux/susfs_def.h>
#endif
BLK
        insert_before common/fs/namespace.c '#include "pnode.h"' "${TMP_BLOCK}"
    fi

    # 3b. extern declarations after a known anchor include.
    # Guard on the DECLARATION, not the bare token — the bare token also
    # matches call sites in hunks that applied successfully, which previously
    # caused this block to be silently skipped (run #8: 13 compile errors in
    # namespace.c from undeclared susfs_is_current_ksu_domain /
    # susfs_is_sdcard_android_data_not_decrypted / CL_COPY_MNT_NS).
    if ! grep -q 'extern bool susfs_is_current_ksu_domain' common/fs/namespace.c; then
        ANCHOR=""
        for a in "trace/hooks/blk.h" "linux/nsproxy.h" "linux/mount.h"; do
            if grep -q "#include <${a}>" common/fs/namespace.c; then
                ANCHOR="${a}"; break
            fi
        done
        if [ -n "${ANCHOR}" ]; then
            cat > "${TMP_BLOCK}" <<'BLK'

#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
extern bool susfs_is_current_ksu_domain(void);
extern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;
#define CL_COPY_MNT_NS BIT(25)
#endif
BLK
            insert_after common/fs/namespace.c "#include <${ANCHOR}>" "${TMP_BLOCK}"
        else
            echo "  [-] namespace.c: no anchor include found" >&2
        fi
    fi

    # Success requires ALL three pieces (include + extern decl + define).
    # The previous weak OR-check (bare token || susfs_def.h) falsely reported
    # OK because susfs_def.h was inserted by block 3a while block 3b was
    # skipped — masking the missing externs until compilation.
    if grep -q 'susfs_def.h' common/fs/namespace.c \
       && grep -q 'extern bool susfs_is_current_ksu_domain' common/fs/namespace.c \
       && grep -q 'CL_COPY_MNT_NS' common/fs/namespace.c; then
        echo "  -> namespace.c OK"; rm -f common/fs/namespace.c.rej
    else
        echo "  [-] namespace.c fix failed (missing extern/CL_COPY_MNT_NS)" >&2
        exit 1
    fi
fi

# ── 4. fs/proc/task_mmu.c (not needed on 6.1) ────────────────
if [ -f "common/fs/proc/task_mmu.c.rej" ]; then
    echo ">>> Skipping task_mmu.c.rej (not needed on 6.1)"
    rm -f common/fs/proc/task_mmu.c.rej
fi

# ── 5. fs/open.c — add susfs_def.h include ───────────────────
if [ -f "common/fs/open.c.rej" ]; then
    echo ">>> Fixing open.c.rej..."
    if ! grep -q 'susfs_def.h' common/fs/open.c; then
        cat > "${TMP_BLOCK}" <<'BLK'
#ifdef CONFIG_KSU_SUSFS
#include <linux/susfs_def.h>
#endif
BLK
        insert_before common/fs/open.c '#include <linux/mount.h>' "${TMP_BLOCK}"
    fi
    if grep -q 'susfs_def.h' common/fs/open.c; then
        echo "  -> open.c OK"; rm -f common/fs/open.c.rej
    else
        echo "  [-] open.c fix failed" >&2
    fi
fi

# ── 6. fs/namei.c (not needed on 6.1) ────────────────────────
if [ -f "common/fs/namei.c.rej" ]; then
    echo ">>> Skipping namei.c.rej"
    rm -f common/fs/namei.c.rej
fi

# ── Final check ─────────────────────────────────────────────
REMAINING="$(find common -type f -name '*.rej' 2>/dev/null || true)"
if [ -n "${REMAINING}" ]; then
    echo "[-] Unresolved rejections (build will likely fail):" >&2
    echo "${REMAINING}" >&2
    exit 1
fi
echo ">>> All patch rejections resolved!"
