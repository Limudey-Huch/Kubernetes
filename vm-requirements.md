# Lab VM Requirements

Everything in this course runs inside **one Ubuntu VM**. Kubernetes is installed with **kubeadm** as a **single-node cluster** (the control-plane node also runs our workloads).

The VM is sized not only for the Kubernetes basics, but also for the later parts of the course, where we add:

- **Argo CD** (GitOps)
- **Prometheus** (metrics)
- **Grafana** (dashboards)

If the VM is sized for kubeadm alone, those tools will cause Pods to be evicted or stuck in `Pending` later. Size it once, correctly.

---

## 1. Hardware

| Resource | Minimum (works, but tight) | Recommended |
|---|---|---|
| vCPU | 4 | **6** |
| RAM | 8 GB | **12–16 GB** |
| Disk | 60 GB | **80 GB**, thin-provisioned, on SSD/NVMe |
| Network adapters | 1 (NAT) | 1 (NAT or Bridged), with a **static IP** |

### Why these numbers

Approximate idle usage on a single-node cluster:

| Component | CPU (requests) | RAM (approx.) |
|---|---|---|
| Ubuntu OS + containerd | ~0.2 | ~0.8 GB |
| Control plane (apiserver, etcd, scheduler, controller-manager) | ~0.7 | ~1.2 GB |
| kube-proxy + CNI + CoreDNS | ~0.3 | ~0.4 GB |
| Argo CD (server, repo-server, application-controller, redis) | ~0.5 | ~1.0 GB |
| Prometheus + Alertmanager + node-exporter + kube-state-metrics | ~0.7 | ~2.0 GB |
| Grafana | ~0.2 | ~0.3 GB |
| **Platform total** | **~2.6 vCPU** | **~5.7 GB** |

The remaining capacity is for **our own lab workloads** (Deployments, scaling labs, StatefulSets, load tests). That is why 4 vCPU / 8 GB is the floor and 6 vCPU / 12–16 GB is comfortable.

Disk: container images, etcd data, Prometheus time-series data (TSDB) and PersistentVolumes all live on the same disk. The kubelet starts **evicting Pods when the disk passes ~85% usage**, so leave plenty of free space.

### Host machine

The physical computer running the VM needs headroom too:

- At least **16 GB RAM** on the host if the VM gets 8 GB; **24–32 GB** if the VM gets 12–16 GB.
- CPU virtualization enabled in BIOS/UEFI (Intel VT-x / AMD-V).
- VMware Workstation / Fusion, VirtualBox, Hyper-V, Parallels or UTM — any hypervisor works.

---

## 2. Operating System

| Item | Requirement |
|---|---|
| OS | **Ubuntu Server 24.04 LTS** (22.04 and 26.04 LTS also work — 26.04 arm64 tested with Kubernetes 1.36) |
| Architecture | amd64 (Intel/AMD) or arm64 (Apple Silicon via UTM / Parallels / VMware Fusion) |
| Desktop | Not required. Server edition is lighter. Use SSH from the host. |
| Kernel | The stock Ubuntu kernel is fine |
| User | A regular user with `sudo` rights |

> Every command in the course runs **inside the VM** (over SSH or the VM console), never on the host machine.

---

## 3. Settings kubeadm checks before install

kubeadm runs "preflight checks". The VM must satisfy these:

| Requirement | Why | How to check |
|---|---|---|
| At least 2 vCPU and 2 GB RAM | Hard preflight check | `nproc`, `free -h` |
| **Swap disabled** | kubelet memory accounting assumes no swap | `swapon --show` (empty output = OK) |
| Unique hostname | Becomes the Node name | `hostnamectl` |
| Unique MAC and `product_uuid` | Matters if you clone VMs | `ip link`, `sudo cat /sys/class/dmi/id/product_uuid` |
| Kernel modules `overlay` + `br_netfilter` | Needed by containerd and Pod networking | `lsmod \| grep -E 'overlay\|br_netfilter'` |
| IP forwarding enabled | Pods route through the node | `sysctl net.ipv4.ip_forward` (should be `1`) |
| Required ports free | 6443, 2379-2380, 10250, 10257, 10259 | `sudo ss -ltnp` |

These are configured in the installation guide — this table is just to show what kubeadm expects.

---

## 4. Networking

### Static IP (important)

`kubeadm init` bakes the node's IP into the API server certificate, etcd and the cluster config. If the IP changes after a reboot (normal DHCP behavior), **the cluster breaks**.

Choose one of:

1. Configure a **static IP** with netplan inside the VM (recommended), or
2. Create a **DHCP reservation** for the VM's MAC in the hypervisor's virtual network.

Check:

```bash
ip -4 addr show
# The cluster-facing address must NOT be marked "dynamic"
```

### IP ranges must not overlap

| Range | Used for | Example |
|---|---|---|
| VM / LAN network | Node IP | `192.168.x.0/24` |
| Pod network (CNI) | Pod IPs | `10.244.0.0/16` |
| Service network | ClusterIP Services | `10.96.0.0/12` |

If your home/office network already uses `10.244.x.x` or `10.96.x.x`, pick different ranges at install time.

### Internet access

The VM needs outbound internet to pull packages and container images (registry.k8s.io, docker.io, quay.io, ghcr.io).

### Host → VM access

Later labs (NodePort, Ingress, Argo CD UI, Grafana UI) are opened from a browser **on the host**. The host must be able to reach the VM IP. With NAT, make sure host-to-VM traffic is allowed (default in VMware/UTM NAT; in VirtualBox use a Host-Only adapter or port forwarding).

---

## 5. Snapshot strategy

Take VM snapshots at these points. They save hours when a lab breaks the cluster:

1. **Clean Ubuntu** — after OS install, updates, static IP, swap off.
2. **Prerequisites done** — after containerd + kubeadm/kubelet/kubectl are installed, before `kubeadm init`.
3. **Cluster ready** — after `kubeadm init` + CNI, node is `Ready`.

---

## 6. Quick pre-install checklist

```bash
nproc                          # >= 4
free -h                        # >= 8Gi total, Swap: 0B
df -h /                        # >= 60G total, plenty free
swapon --show                  # empty
hostnamectl                    # hostname set, unique
ip -4 addr show                # static address, not "dynamic"
ping -c 2 registry.k8s.io      # internet + DNS work
```

- [ ] 4+ vCPU (6 recommended)
- [ ] 8+ GB RAM (12–16 GB recommended)
- [ ] 60+ GB disk (80 GB recommended)
- [ ] Ubuntu Server 24.04 LTS
- [ ] Swap disabled permanently (removed from `/etc/fstab`)
- [ ] Static IP on the cluster-facing interface
- [ ] Unique hostname
- [ ] Internet access from the VM
- [ ] Host can reach the VM IP
- [ ] Snapshot taken
