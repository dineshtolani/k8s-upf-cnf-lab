#!/usr/bin/env bash
# Bridge locally built Docker images into containerd's k8s.io namespace.
# Run as root.
set -euo pipefail

BESS_IMAGE="${BESS_IMAGE:-upf-bess:2.6.4-dev}"
PFCP_IMAGE="${PFCP_IMAGE:-upf-pfcp:2.6.4-dev}"

echo "[+] Saving images from Docker..."
docker save "${BESS_IMAGE}" -o /tmp/bess-local.tar
docker save "${PFCP_IMAGE}" -o /tmp/pfcp-local.tar

echo "[+] Importing into containerd k8s.io namespace..."
ctr -n=k8s.io images import /tmp/bess-local.tar
ctr -n=k8s.io images import /tmp/pfcp-local.tar

echo "[+] Verifying..."
ctr -n=k8s.io images list | grep -E "upf-bess|upf-pfcp"

echo "[+] Done. Use imagePullPolicy: Never in the pod spec."