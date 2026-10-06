# Kubernetes CNF Lab — UPF Deployment

## Environment
- Single-node kubeadm cluster on Rocky Linux 9.8 (VMware Workstation guest)
- Kubernetes v1.37.0, containerd 2.3.5
- Node: k8snode1, 4 vCPU, 15 GiB RAM
- 3 x 1 GiB HugePages reserved via grubby (BLS)

## Components
- **Multus CNI**: multi-network attachment
- **ipvlan L2** on `ens192`: secondary data-plane interface for the UPF pod
- **SD-Core BESS-UPF 2.6.4-dev**: locally built, AF_PACKET mode
- **Static IP pinning**: 192.168.170.190 on net1

## Known Constraints
- IOMMU groups are empty on VMware guest — DPDK/VFIO not possible
- Pivoted to AF_PACKET datapath; CNDP/AF_XDP as future path
- macvlan blocked by VMware Workstation MAC filtering → ipvlan used
