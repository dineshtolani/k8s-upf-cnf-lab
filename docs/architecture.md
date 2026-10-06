
# Architecture & Design Decisions

## Network Topology

The pod is **multi-homed** via Multus:

| Interface | CNI | IP | Purpose |
|---|---|---|---|
| eth0 | Calico (VXLAN) | 192.168.249.x/32 | Cluster-internal: kubelet, DNS, N4 via Service |
| net1 | ipvlan L2 on ens192 | 192.168.170.190/24 | Data plane: N3 (GTP-U), N6 |

`eth0` provides pod-to-cluster networking (DNS resolution for CoreDNS,
API server reachability, etc.). `net1` is a flat L2 attachment on the same
subnet as the node's secondary NIC.

## Why ipvlan Instead of macvlan

macvlan assigns each child interface its own MAC. VMware Workstation's virtual
switch drops frames with unrecognized source MACs (anti-spoofing). ipvlan
reuses the parent NIC's MAC, so VMware is satisfied.

| Feature | macvlan | ipvlan L2 |
|---|---|---|
| MAC per child | Unique | Shared with parent |
| VMware Workstation | ❌ Frames dropped | ✅ Works |
| L2 identity to peers | Distinct | Shared |
| L3 connectivity from outside | ✅ | ✅ |

## Why AF_PACKET Instead of DPDK

DPDK requires `vfio-pci` binding, which requires IOMMU groups. VMware
Workstation guests do not expose VT-d, so no IOMMU groups exist. AF_PACKET
avoids this entirely by using standard Linux raw sockets.

| Aspect | DPDK | AF_PACKET |
|---|---|---|
| IOMMU required | Yes | No |
| HugePages required | Yes | Optional |
| Bare metal / KVM only | Yes | No |
| Throughput (Gbps) | 10-100+ | 1-10 |
| Correct for this lab | No | Yes |

AF_PACKET is the correct datapath for a virtualized lab. The DPDK path would
require bare metal or a KVM host with vIOMMU.

## HugePages

3 × 1 GiB pages reserved at boot via `grubby`. The UPF pod requests 1 GiB,
mounted at `/dev/hugepages`. Even in AF_PACKET mode, BESS uses hugepages for
its UMEM packet pool to reduce TLB misses.

## Containerd vs Docker

The cluster uses containerd. Docker's image store and containerd's are
independent. Locally built images must be exported with `docker save` and
imported with `ctr -n=k8s.io images import`.

## Component Interaction

SMF ─── PFCP (N4) :8805 ───► pfcpiface
│
│ gRPC :10514
▼
bessd
│
│ AF_PACKET
▼
net1 (N3/N6)


`pfcpiface` translates PFCP session rules (PDR/FAR/QER) into BESS pipeline
instructions via a local gRPC socket on `127.0.0.1:10514`. BESS then handles
GTP-U encapsulation/decapsulation on `net1`.

