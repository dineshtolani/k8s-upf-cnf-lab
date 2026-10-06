# Troubleshooting Log

Every blocker encountered during the build-out, with root cause and resolution.
This is the reference for anyone (including future me) reproducing the lab.

---

## Issue #1 — HugePages Not Applied After Reboot

**Symptom**
After editing `/etc/default/grub` and running `grub2-mkconfig -o /boot/grub2/grub.cfg`,
`/proc/meminfo` still showed `HugePages_Total: 0` and `Hugepagesize: 2048 kB`.

**Root Cause**
Rocky Linux 9.5+ (and RHEL 9.5+) use the Boot Loader Specification (BLS) with
`GRUB_ENABLE_BLSCFG=true`. Editing `/etc/default/grub` and running `grub2-mkconfig`
no longer updates the kernel command line for existing BLS entries.

**Fix**
Use `grubby` to modify the kernel command line directly:
grubby --update-kernel=ALL
--args="default_hugepagesz=1G hugepagesz=1G hugepages=3 intel_iommu=on iommu=pt"
reboot


**Verification**
cat /proc/cmdline
grep -i huge /proc/meminfo

Expected:
HugePages_Total: 3
Hugepagesize: 1048576 kB


---

## Issue #2 — IOMMU Groups Empty (DPDK/VFIO Not Possible)

**Symptom**
iommu: Default domain type: Passthrough (set via kernel command line)

ls /sys/kernel/iommu_groups/
(no output)


**Root Cause**
VMware Workstation does not expose VT-d to guest VMs, even with
"Expose hardware assisted virtualization to guest OS" enabled. That option
exposes VT-x (CPU virtualization) but not VT-d (I/O virtualization). Without
VT-d, the kernel has no IOMMU groups and `vfio-pci` passthrough is impossible.

**Impact**
Native DPDK is not possible in this VM. No amount of guest-side configuration
changes this — it requires either bare metal, a KVM host with vIOMMU, or a
physically passed-through NIC.

**Resolution**
Pivoted the datapath from DPDK to AF_PACKET (via BESS). This is the correct
engineering decision for a virtualized environment.

**Root Cause**
The node has only **2 allocatable vCPUs**, and ~950m is already consumed by
system pods (Calico, kube-proxy, CoreDNS, control-plane static pods). The UPF
pod requested 3 CPU total (2 for BESS + 1 for pfcpiface), which could not fit.

**Fix**
Reduce CPU **requests** (not limits) to fit within the available headroom.
Kubernetes only schedules based on requests; limits still allow bursting.

**Reference**
- Linux kernel docs: VFIO requires an IOMMU capable of DMA remapping.
- VMware KB: VT-d passthrough requires DirectPath I/O, configured on the ESXi
  host, not in the guest.

---

## Issue #3 — Multus Pods Pending (Insufficient CPU)

**Symptom**

Warning FailedScheduling 0/1 nodes are available: 1 Insufficient cpu.


**Root Cause**
The node has only **2 allocatable vCPUs**, and ~950m is already consumed by
system pods (Calico, kube-proxy, CoreDNS, control-plane static pods). The UPF
pod requested 3 CPU total (2 for BESS + 1 for pfcpiface), which could not fit.

**Fix**
Reduce CPU **requests** (not limits) to fit within the available headroom.
Kubernetes only schedules based on requests; limits still allow bursting.

bess container

requests: { cpu: "500m", memory: "1Gi", hugepages-1Gi: "1Gi" }
limits: { cpu: "1500m", memory: "2Gi", hugepages-1Gi: "1Gi" }
pfcpiface container

requests: { cpu: "250m", memory: "256Mi" }
limits: { cpu: "500m", memory: "512Mi" }


**Long-term Fix**
Resize the VM to 8 vCPU / 24 GiB before deploying the full SD-Core control plane.

---

## Issue #4 — macvlan Fails on VMware Workstation

**Symptom**
A macvlan NAD on `ens192` worked from inside the pod, but:
- `ping 192.168.170.171` (the node's own ens192 IP) failed with `Destination Host Unreachable`
- `ping <pod-ip>` from the laptop failed with 100% packet loss

**Root Cause**
Two separate issues:
1. **Kernel restriction:** macvlan children cannot communicate with the parent
   interface by design, to prevent L2 loops. Expected behavior.
2. **VMware MAC filtering:** VMware Workstation's virtual switch drops frames
   whose source MAC does not match the VM's registered NIC MAC. macvlan
   generates a new MAC per pod, so those frames are silently dropped.

**Fix**
Switch the NAD from `macvlan` to **`ipvlan` in L2 mode**. ipvlan reuses the
parent NIC's MAC, so VMware's MAC filter is satisfied. The pod still gets a
distinct IP on the same subnet.

```json
{
  "cniVersion": "0.3.1",
  "type": "ipvlan",
  "master": "ens192",
  "mode": "l2",
  "ipam": {
    "type": "host-local",
    "subnet": "192.168.170.0/24",
    "rangeStart": "192.168.170.180",
    "rangeEnd": "192.168.170.200"
  }
}

Note
The pod → node ping still fails with ipvlan (same kernel restriction), and
that is expected. It does not affect the UPF use case.
Issue #5 — UPF Image Not Found (ImagePullBackOff)

Symptom

Failed to pull image "omecproject/upf-epc-bess:local":
  docker.io/omecproject/upf-epc-bess:local: not found

Root Cause
The image was built locally with make docker-build, which stores it in the
Docker image store (/var/lib/docker). But the cluster uses containerd
(/var/lib/containerd), and kubelet only reads from containerd's k8s.io
namespace. The two stores are independent.

Fix
Bridge Docker → containerd:
docker save upf-bess:2.6.4-dev -o bess-local.tar
docker save upf-pfcp:2.6.4-dev -o pfcp-local.tar
ctr -n=k8s.io images import bess-local.tar
ctr -n=k8s.io images import pfcp-local.tar

Then set imagePullPolicy: Never on the pod so kubelet doesn't try the registry.

Gotcha
If the tag is reused after a rebuild, containerd may still point at the old
digest. Remove the old tag first:

ctr -n=k8s.io images rm docker.io/library/upf-bess:2.6.4-dev
ctr -n=k8s.io images import bess-local.tar

## Issue #6 — BESS Container: sudo: not found
Symptom


/bin/sh: : sudo: not found
*** Error: Cannot start BESS daemon
  Command failed: daemon start

Root Cause
The bessctl wrapper script (a Python tool) invokes sudo internally. The
minimal container image has no sudo binary and does not need one (the
container runs as root). bessctl daemon start is also the wrong entry point
for a container — the image's native entrypoint is bessd -f.

Fix
Bypass bessctl and run bessd directly in foreground mode:
args:
- |
  /usr/bin/bessd -f /conf/upf.json
-f keeps bessd in the foreground as PID 1, which is what Kubernetes
expects. Logs go to stdout and are visible via kubectl logs.

Verification

kubectl logs upf-bess -c bess | grep "Server listening"
# I... bessctl.cc:1935] Server listening on 127.0.0.1:10514

Issue #7 — pfcpiface: unrecognized level: "trace"

Symptom


FATAL pfcpiface/main.go:24 error reading conf file: unrecognized level: "trace"

Root Cause
The log_level field in upf.json was set to "trace", which is not a valid
level for this version of pfcpiface. Valid levels are debug, info, warn,
error.

Fix
Change "log_level": "trace" to "log_level": "debug" in the ConfigMap, then
delete and recreate the pod (ConfigMap changes do not restart running pods).

Gotcha
Editing the live ConfigMap with kubectl edit does not persist if the file
upf-pod.yaml is later re-applied. The file is the source of truth — edit the
file, then re-apply.

Issue #8 — pfcpiface: unable to resolve hostname upf

Symptom

FATAL pfcpiface/upf.go:149 unable to resolve hostname upf
  lookup upf on 10.96.0.10:53: server misbehaving

Root Cause
The ConfigMap had "hostname": "upf", which becomes the PFCP NodeID. The
pfcpiface process tries to resolve that hostname via cluster DNS (CoreDNS),
which has no record for upf, so CoreDNS returns SERVFAIL.

Fix
Set the NodeID to a literal IP address that matches the pod's data-plane
interface. Also pin that IP in the Multus annotation so it stays constant
across restarts:
 annotations:
  k8s.v1.cni.cncf.io/networks: '[
    { "name": "upf-ipvlan", "interface": "net1",
      "ips": ["192.168.170.190/24"] }
  ]'

"cpiface": { "hostname": "192.168.170.190", ... }

Verification

kubectl logs upf-bess -c pfcpiface | grep NodeID
# ... CPIface:{... NodeID:192.168.170.190 ...}

Issue #9 — pfcpiface Logs "DeadlineExceeded" Clearing BESS State

ERROR pfcpiface/bess.go:1087 pdrLookup clear did not complete: DeadlineExceeded
ERROR pfcpiface/bess.go:923  failed to clear pdrLookup: ...

Root Cause
On startup, pfcpiface clears all PDR/FAR/QER state in BESS to start from a
clean slate. BESS was just launched and has no datapath ports bound yet
(0 DPDK PMD ports have been recognized), so the lookups have nothing to
respond to and the RPCs time out. This is cosmetic — pfcpiface logs the
timeouts and continues.

Impact
None. BESS binds ports dynamically when the SMF installs PDRs referencing
net1. The 0 ports line at startup is expected for AF_PACKET mode.

Verification of healthy state
kubectl logs upf-bess -c pfcpiface | grep "listening for new PFCP"


# INFO pfcpiface/node.go:84 listening for new PFCP connections on [::]:8805

Issue #10 — Empty kubectl logs --previous for Fast-Crashing Containers

Symptom
unable to retrieve container logs for containerd://...

crictl ps -a | grep upf-bess
crictl logs <container-id>

ls /var/log/pods/default_upf-bess_<POD_UID>/
cat /var/log/pods/default_upf-bess_<POD_UID>/bess/*.log

crictl is not installed by default on Rocky; install it and point it at
containerd:

cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint:   unix:///run/containerd/containerd.sock
timeout: 10
EOF

