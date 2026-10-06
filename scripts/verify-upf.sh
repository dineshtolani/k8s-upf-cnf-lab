#!/usr/bin/env bash
# Quick health check for the UPF pod.
set -euo pipefail

echo "[+] Pod status:"
kubectl get pod upf-bess -o wide

echo
echo "[+] Interfaces inside the pod:"
kubectl exec upf-bess -c bess -- ip -4 addr show

echo
echo "[+] BESS listening check:"
kubectl logs upf-bess -c bess | grep -i "Server listening" || true

echo
echo "[+] PFCP listener check:"
kubectl logs upf-bess -c pfcpiface | grep -i "listening for new PFCP" || true

echo
echo "[+] NodeID in pfcpiface config:"
kubectl logs upf-bess -c pfcpiface | grep -o "NodeID:[0-9.]*" || true