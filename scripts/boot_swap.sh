#!/usr/bin/env bash
set -euo pipefail

# Swaps the kernel Image inside a boot.img using magiskboot.
# Preserves the original ramdisk, dtb, cmdline, etc.

BOOT_IMG=""
KERNEL_IMAGE=""
MAGISKBOOT="./tools/magiskboot"
OUTDIR="out/final"
OUTNAME="boot.img"
WORKDIR="work/repack-tmp"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --boot)        BOOT_IMG="$2"; shift 2 ;;
        --image)       KERNEL_IMAGE="$2"; shift 2 ;;
        --magiskboot)  MAGISKBOOT="$2"; shift 2 ;;
        --outdir)      OUTDIR="$2"; shift 2 ;;
        --outname)     OUTNAME="$2"; shift 2 ;;
        --workdir)     WORKDIR="$2"; shift 2 ;;
        *) echo "Unknown: $1"; exit 1 ;;
    esac
done

[ -f "$BOOT_IMG" ]      || { echo "[-] boot.img not found: $BOOT_IMG"; exit 1; }
[ -f "$KERNEL_IMAGE" ]  || { echo "[-] kernel Image not found: $KERNEL_IMAGE"; exit 1; }
[ -x "$MAGISKBOOT" ]    || { echo "[-] magiskboot not executable: $MAGISKBOOT"; exit 1; }

mkdir -p "$OUTDIR" "$WORKDIR"
cd "$WORKDIR"

echo ">>> Unpacking boot.img..."
cp -f "$BOOT_IMG" ./boot.img
"$MAGISKBOOT" unpack -h ./boot.img

echo ">>> Replacing kernel Image..."
cp -f "$KERNEL_IMAGE" ./kernel

echo ">>> Repacking boot.img..."
"$MAGISKBOOT" repack ./boot.img new-boot.img

echo ">>> Verifying..."
if [ -f "new-boot.img" ]; then
    SIZE=$(stat -c%s new-boot.img)
    echo "    Output: ${OUTDIR}/${OUTNAME} (${SIZE} bytes)"
    mv -f new-boot.img "${OUTDIR}/${OUTNAME}"
    echo ">>> Boot image repacked!"
else
    echo "[-] Repack failed — new-boot.img not produced" >&2
    exit 1
fi

cd ..
rm -rf "$WORKDIR"