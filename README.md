# KernelSU-Next + SUSFS Builder for Pixel 7 (panther)

CI pipeline for building a custom GKI kernel with **KernelSU-Next** (pershoot fork, SUSFS hooks pre-applied) and optional **SUSFS** kernel patches.

Based on [shoey63/Kernel-Builder-GKI-Susfs](https://github.com/shoey63/Kernel-Builder-GKI-Susfs) architecture, adapted for pershoot's repos.

## Key Differences from shoey63's Builder

| | shoey63 | This repo |
|---|---------|-----------|
| **KernelSU** | `shoey63/KernelSU-Next` (ci-runner) | `pershoot/KernelSU-Next` (SUSFS hooks built-in) |
| **SUSFS** | `shoey63/susfs4ksu` (gki branch) | `pershoot/susfs4ksu` (aosp-android14-6.1-dev) |
| **KSU patch from susfs4ksu** | Applied | **NOT applied** (already in pershoot/KernelSU-Next) |
| **Date spoofing** | Google commit timestamp | Google commit timestamp (or custom) |

## Why pershoot's Forks?

- `pershoot/KernelSU-Next` already contains SUSFS kernel hooks — no need for the separate `10_enable_susfs_for_ksu.patch`
- `pershoot/susfs4ksu` has the matching kernel-only patches on the `aosp-android14-6.1-dev` branch
- Confirmed by KernelSU-Next developer (@rifsxd)

## Build Date Spoofing

The workflow captures Google's actual git commit timestamp from the kernel source:
```
OFFICIAL_DATE=$(git log -1 --format=%ct)
```

This is passed to Bazel as `SOURCE_DATE_EPOCH`, which controls the `__DATE__`/`__TIME__` macros and the kernel's `uname -v` timestamp. The git hash is also injected via `STABLE_BUILD_VERSION` and `KLEAF_KERNEL_BUILD_VERSION`.

**Result:** The output kernel's version string matches the stock kernel's date and hash.

### Custom Timestamp

If you need a specific date (e.g., `Wed Jan 28 05:34:14 UTC 2026`), provide the Unix epoch in the `spoof_timestamp` input:
```
date -d "2026-01-28 05:34:14 UTC" +%s
# → 1769578454
```

## How to Use

### 1. Fork/clone this repo

### 2. Go to **Actions** → **KernelSU-Next + SUSFS Builder** → **Run workflow**

### 3. Fill in inputs:

| Input | Example | Description |
|-------|---------|-------------|
| `target_version` | `6.1.157` | Kernel version to target |
| `manifest_branch` | *(blank)* | Auto-resolved to `common-android14-6.1-lts` |
| `enable_susfs` | `true` | Enable SUSFS kernel patches |
| `ota_url` | `https://...ota.zip` | OTA for boot.img repack (blank = AnyKernel3 zip) |
| `ksu_tag` | *(blank)* | Specific KSU-Next tag (blank = latest release) |
| `spoof_timestamp` | `1769578454` | Custom Unix timestamp for build date |

### 4. Download artifacts

- **Kernel**: `panther-KSU-Next-boot` (repacked boot.img) or `panther-KSU-Next-AK3` (flashable zip)
- Flash via KernelSU app or TWRP

## Post-Flash

1. Install [KernelSU manager](https://github.com/KernelSU-Next/KernelSU-Next/releases)
2. If SUSFS enabled — install [susfs4ksu-module](https://github.com/sidex15/susfs4ksu-module) from KernelSU
3. **Do NOT** install shamiko or zygisk-assistant alongside SUSFS

## Pipeline Steps

```
┌─ Sync kernel source (repo + manifest)
├─ Capture Google hash + timestamp
├─ Inject KernelSU-Next (pershoot fork + Gatekeeper overrides)
├─ Integrate SUSFS kernel patches (pershoot/susfs4ksu)
├─ Fix SUSFS patch rejections (sed-based)
├─ Configure Kconfigs (ABI neutralize + KSU/SUSFS options)
├─ Build via Kleaf/Bazel (SOURCE_DATE_EPOCH + hash spoofing)
├─ [Optional] Pull boot.img from OTA via payload_dumper
├─ [Optional] Repack boot.img via magiskboot
└─ [Fallback] Generate AnyKernel3 zip
```

## Repository Structure

```
.
├── .github/workflows/
│   └── build.yml                 # CI pipeline
├── scripts/
│   ├── inject_ksu_next.sh        # pershoot/KernelSU-Next + Gatekeeper
│   ├── integrate_susfs.sh        # pershoot/susfs4ksu kernel patches only
│   ├── fix_susfs_rejections.sh   # Auto-fix known .rej files
│   ├── build_kernel.sh           # Kleaf/Bazel build with date spoof
│   ├── configure_kconfigs.sh     # ABI neutralize + config fragments
│   ├── validate_ota.py           # Check OTA URL validity
│   ├── ota_pull.py               # Extract boot.img from OTA
│   └── boot_swap.sh              # Swap kernel in boot.img
├── tools/
│   └── (magiskboot binary)
└── README.md
```

## Credits

- [shoey63/Kernel-Builder-GKI-Susfs](https://github.com/shoey63/Kernel-Builder-GKI-Susfs) — Architecture reference
- [pershoot/KernelSU-Next](https://github.com/pershoot/KernelSU-Next) — KSU fork with SUSFS hooks
- [pershoot/susfs4ksu](https://gitlab.com/pershoot/susfs4ksu) — SUSFS kernel patches
- [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) — by @rifsxd
- [susfs4ksu-module](https://github.com/sidex15/susfs4ksu-module) — Userspace SUSFS module

## License

MIT