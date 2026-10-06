#!/usr/bin/env bash
# Reserve 1G HugePages on Rocky/RHEL 9.x using grubby (BLS-aware).
# Run as root.
set -euo pipefail

HUGEPAGES="${HUGEPAGES:-3}"

echo "[+] Applying kernel args via grubby..."
grubby --update-kernel=ALL \
  --args="default_hugepagesz=1G hugepagesz=1G hugepages=${HUGEPAGES} intel_iommu=on iommu=pt"

echo "[+] Verifying BLS entry..."
grep -h options /boot/loader/entries/*.conf | head -1

echo "[+] A reboot is required. After reboot, verify with:"
echo "    cat /proc/cmdline"
echo "    grep -i huge /proc/meminfo"