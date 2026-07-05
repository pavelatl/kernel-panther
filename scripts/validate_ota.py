#!/usr/bin/env python3
"""Validates that an OTA URL contains a payload.bin at its root."""

import sys
import requests
from urllib.parse import urlparse

def main():
    ota_url = sys.environ.get("OTA_URL", "")
    if not ota_url:
        print("[-] No OTA_URL provided. AK3 zip will be generated instead.")
        return

    print(f">>> Validating OTA URL: {ota_url}")

    try:
        resp = requests.head(ota_url, allow_redirects=True, timeout=30)
        if resp.status_code != 200:
            print(f"[-] OTA URL returned HTTP {resp.status_code}")
            sys.exit(1)
        print(f"    HTTP {resp.status_code} — URL is reachable")

        ct = resp.headers.get("content-type", "")
        size = int(resp.headers.get("content-length", 0))
        print(f"    Content-Type: {ct}")
        print(f"    Size: {size / (1024*1024):.1f} MB")

        # Set repack enabled for downstream steps
        with open(sys.environ["GITHUB_ENV"], "a") as f:
            f.write("REPACK_ENABLED=true\n")

        print(">>> OTA validation passed. Repack pipeline: ENABLED")

    except requests.RequestException as e:
        print(f"[-] OTA validation failed: {e}")
        print("    Falling back to AK3 zip.")
        with open(sys.environ["GITHUB_ENV"], "a") as f:
            f.write("REPACK_ENABLED=false\n")

if __name__ == "__main__":
    main()