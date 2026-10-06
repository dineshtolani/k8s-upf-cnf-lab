# Performance Notes

## What This Lab Demonstrates

- Correctness of 5G UPF deployment on Kubernetes
- Multi-NIC CNF pattern (Multus + ipvlan)
- HugePages allocation to a pod
- PFCP (N4) control-plane reachability
- AF_PACKET datapath initialization

## What This Lab Does NOT Demonstrate

- DPDK-class throughput (not possible on this hypervisor)
- Production-grade latency (no CPU pinning, no isolcpus)
- High session scale (no CPU isolation, small VM)

## Expected Throughput

On a 4 vCPU / 15 GiB VMware guest with AF_PACKET, expect single-digit Gbps
at best, likely lower under load. This is a **functional lab**, not a
performance benchmark.

## Realistic Next Steps for Higher Performance

1. Deploy on bare metal with a physical NIC bound to `vfio-pci`, and use BESS
   in DPDK mode.
2. Use a KVM host with vIOMMU enabled and pass a NIC through to the guest.
3. Use CNDP/AF_XDP in the container to reduce kernel overhead.
4. Enable CPU Manager static policy and isolate cores via `isolcpus`.

## Caveat on VM CPU Contention

The i7-1355U is a 15W U-series chip. If the hypervisor is doing anything else,
guest performance will be jittery. For any meaningful benchmark, use a
dedicated host.