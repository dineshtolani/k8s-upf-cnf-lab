# Kubernetes CNF Lab — 5G UPF Deployment

A hands-on lab deploying a containerized 5G User Plane Function (UPF) on a
single-node Kubernetes cluster, exercising Multi-NIC CNI (Multus), HugePages,
and a software datapath (BESS/AF_PACKET).

The lab documents the *full journey*, including a DPDK path that was ruled out
due to hypervisor limitations and the pivot to an AF_PACKET datapath — which
is a realistic, production-relevant engineering decision.

---

## Environment

| Layer | Version / Spec |
|---|---|
| Hypervisor | VMware Workstation (nested, guest) |
| OS | Rocky Linux 9.8 |
| Kernel | 5.14.0-687.46.1.el9_8.x86_64 |
| Kubernetes | v1.37.0 (kubeadm, single node) |
| Runtime | containerd 2.3.5 |
| CNI (primary) | Calico (VXLAN) |
| CNI (secondary) | Multus + ipvlan L2 |
| Host vCPU / RAM | 4 vCPU / 15 GiB |
| HugePages | 3 x 1 GiB (1G pages) |
| Secondary NIC | ens192 (192.168.170.171/24) |

---

## What Was Deployed

+----------------------+ +-------------------------------+
| Node (Rocky 9.8) | | Pod: upf-bess |
| | | |
| ens160 ------------+-Calico----+- eth0 192.168.249.x/32 |
| ens192 ------------+-ipvlan----+- net1 192.168.170.190/24 |
| | | |
| HugePages: 3 x 1G |--mounted--+- /dev/hugepages (1Gi) |
+----------------------+ | |
| +-----------+ +-----------+ |
| | bessd | | pfcpiface | |
| | (N3/N6) | | (N4) | |
| +-----------+ +-----------+ |
+-------------------------------+


- **UPF datapath:** BESS (Berkeley Extensible Software Switch) in **AF_PACKET** mode
- **Control interface:** PFCP (N4) listening on `:8805`
- **Data interface:** GTP-U on `net1` (`192.168.170.190`)
- **Image:** Locally built `upf-bess:2.6.4-dev` and `upf-pfcp:2.6.4-dev`

---

## Deliverables

- [x] HugePages reserved on the host and exposed to the Kubernetes scheduler
- [x] Multus CNI installed and validated with a multi-homed test pod
- [x] ipvlan NetworkAttachmentDefinition on a dedicated secondary NIC
- [x] UPF pod with two containers (BESS + PFCP agent) reaching `2/2 Running`
- [x] PFCP server listening on `:8805`
- [x] Full troubleshooting narrative documenting every blocker and its fix

---

## Repository Layout

- `manifests/` — Kubernetes YAML (NAD, ConfigMap, Pod)
- `scripts/` — Node setup and image import helpers
- `docs/troubleshooting.md` — Every issue encountered, with root cause and fix
- `docs/architecture.md` — Design decisions and alternatives considered
- `docs/performance-notes.md` — Expected datapath behavior in this environment

---

## Quick Start

See `docs/architecture.md` and `manifests/` for the exact working configuration.

```bash
# 1. Reserve hugepages on the node
sudo bash scripts/setup-node-hugepages.sh

# 2. Build and load UPF images into containerd
sudo bash scripts/import-images-to-containerd.sh

# 3. Apply manifests
kubectl apply -f manifests/upf-ipvlan-nad.yaml
kubectl apply -f manifests/upf-pod.yaml

# 4. Verify
bash scripts/verify-upf.sh
