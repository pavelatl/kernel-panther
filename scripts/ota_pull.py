#!/usr/bin/env python3
"""Pulls a specific partition image from an OTA ZIP via payload-dumper-go."""

import argparse
import os
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, help="OTA ZIP URL or path")
    parser.add_argument("--partition", default="boot", help="Partition name")
    parser.add_argument("--outdir", default="work/stock", help="Output directory")
    parser.add_argument("--bin", default=None, help="Path to payload-dumper-go binary")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    binary = args.bin or shutil.which("payload-dumper-go") or "payload-dumper-go"

    cmd = [
        binary,
        "--partition", args.partition,
        "--output", args.outdir,
        args.source,
    ]

    print(f">>> Pulling {args.partition} from OTA via {binary}...")
    result = subprocess.run(cmd)

    if result.returncode != 0:
        print(f"[-] payload-dumper-go failed (rc={result.returncode})")
        sys.exit(1)

    print(f">>> Partition image extracted to {args.outdir}/")


if __name__ == "__main__":
    main()
