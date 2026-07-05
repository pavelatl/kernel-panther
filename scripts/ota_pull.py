#!/usr/bin/env python3
"""Pulls a specific partition image from an OTA ZIP via payload_dumper."""

import argparse
import os
import subprocess
import sys

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, help="OTA ZIP URL")
    parser.add_argument("--partition", default="boot", help="Partition name")
    parser.add_argument("--outdir", default="work/stock", help="Output directory")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    cmd = [
        "payload_dumper-go",
        "--partition", args.partition,
        "--output", args.outdir,
        args.source,
    ]

    print(f">>> Pulling {args.partition} from OTA...")
    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"[-] payload_dumper failed:\n{result.stderr}")
        sys.exit(1)

    print(f">>> Partition image extracted to {args.outdir}/")

if __name__ == "__main__":
    main()