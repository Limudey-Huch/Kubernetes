# 01 — Platform Architecture

What the installation built, which components make up the cluster, and how each one runs on your VM.

**Before you start:** a working cluster from the [installation guide](../installation-guide.md) (`kubectl get nodes` shows `Ready`).

This chapter explains. The hands-on part is in the [exercises](exercises/README.md), where you find every component yourself.

---

## Goals

By the end of this chapter you can:

- Explain what each installation step did and why it was needed.
- Name the cluster components and say **how** each one runs: systemd service, static Pod or regular Pod.
- Explain the difference between `kubectl` and `crictl`.
- Tell namespaced resources from cluster-wide resources.
- Describe how a Pod gets connected to the network.

---

## 1. What the installation did

`02-install-k8s.sh` ran these steps. Each one exists for a reason:

| Step | What it did | Why |
|---|---|---|
| Swap off | `swapoff -a` and removed swap from `/etc/fstab` | The kubelet calculates Pod memory assuming there is no swap |
| Kernel modules | Loaded `overlay` and `br_netfilter` | `overlay`: the filesystem for image layers. `br_netfilter`: lets iptables see traffic that crosses a Linux bridge (Pod traffic) |
| sysctl | `ip_forward = 1`, `bridge-nf-call-iptables = 1` | The node must route packets between Pods and the outside world |
| containerd | Installed it and set `SystemdCgroup = true` | Kubernetes does not run containers itself. containerd and the kubelet must use the **same** cgroup driver, otherwise Pods restart randomly |
| Packages | `kubeadm`, `kubelet`, `kubectl`, `cri-tools`, held with `apt-mark hold` | Kubernetes upgrades must be done in a controlled order, never by a random `apt upgrade` |
| `kubeadm init` | Created certificates, kubeconfig files, etcd and the control plane | Builds the cluster. `--apiserver-advertise-address` is the node IP (baked into certificates — that is why the IP must be static). `--pod-network-cidr=10.244.0.0/16` is the Pod IP range |
| Flannel | Installed the CNI plugin | Kubernetes defines the network interface (CNI) but ships no network. Until a CNI exists the node is `NotReady` |
| Remove taint | Removed `node-role.kubernetes.io/control-plane:NoSchedule` | In production, apps run on worker nodes. We have one node, so it must also run our apps |

---

## 2. The architecture on one VM

```text
                   kubectl
                      │  HTTPS :6443
                      ▼
               kube-apiserver ◄──► etcd
                      ▲
        ┌─────────────┴─────────────┐
 controller-manager             scheduler
                      │
                      ▼
                   kubelet  (systemd service)
                      │  CRI
                      ▼
                  containerd
                      │
                      ▼
                  Containers

   CoreDNS ── service discovery     Flannel ── Pod network
```

Two rules explain the whole picture:

- **Everything goes through the API server.** `kubectl`, the scheduler, the controllers and the kubelet all talk only to kube-apiserver. Only the API server talks to etcd.
- **etcd is the only place state is stored.** Every Deployment, Service and Secret lives there. Losing etcd without a backup means losing the cluster.

---

## 3. How each component runs

The components do not all run the same way:

| Component | Runs as | Namespace | Port | Job |
|---|---|---|---|---|
| containerd | systemd service | — | — | Runs every container, through the CRI |
| kubelet | systemd service | — | 10250 | Node agent: starts Pods, reports node status |
| kube-apiserver | static Pod | `kube-system` | **6443** | The front door. All requests come here |
| etcd | static Pod | `kube-system` | 2379, 2380 | The cluster database |
| kube-scheduler | static Pod | `kube-system` | 10259 (health) | Picks a node for each new Pod |
| kube-controller-manager | static Pod | `kube-system` | 10257 (health) | Runs the controllers (chapter 02) |
| kube-proxy | DaemonSet | `kube-system` | 10256 (health) | Programs Service routing rules on the node |
| CoreDNS | Deployment | `kube-system` | 53 (inside the cluster) | DNS names for Services |
| Flannel | DaemonSet | `kube-flannel` | — | Pod network |

### Why three different ways?

```text
systemd ──starts──► containerd + kubelet
                          │
                          │ kubelet reads /etc/kubernetes/manifests/
                          ▼
                    static Pods: etcd, kube-apiserver,
                                 scheduler, controller-manager
                          │
                          │ now the API server is up
                          ▼
                    regular Pods: kube-proxy, Flannel, CoreDNS, your apps
```

- **systemd services** — the kubelet runs Pods, so it cannot itself be a Pod. Something outside Kubernetes must start it.
- **static Pods** — the control plane is needed *before* there is an API server to ask. The kubelet runs these straight from YAML files in `/etc/kubernetes/manifests/`, which `kubeadm init` wrote. To change one, you edit the file; deleting the Pod with `kubectl` does not remove it.
- **regular Pods** — once the API server is up, everything else is managed the normal Kubernetes way. A **DaemonSet** runs one copy on every node, which is what node-level networking needs.

Static Pod names end with the node name: `kube-apiserver-k8s-lab`.

### Ports: who can reach what

Each component listens only where it has to:

```text
*:PORT           reachable from anywhere     (6443 API server, 10250 kubelet)
127.0.0.1:PORT   reachable only on the node  (health checks, metrics)
```

The scheduler and controller-manager have only health ports because they never receive requests — they **call** the API server.

---

## 4. kubectl vs crictl

| Tool | Talks to | Sees | Use it for |
|---|---|---|---|
| `kubectl` | kube-apiserver | The whole cluster: Deployments, Services, namespaces... | Everything, day to day |
| `crictl` | containerd, on **this node only** | Pods and containers only | Low-level debugging on a node |

Docker is not part of the cluster at all. containerd runs every container — your apps and Kubernetes' own components.

If you kill a container with `crictl`, the kubelet notices and starts it again. The desired state lives in the API, not in the runtime.

---

## 5. Namespaces

A **namespace** is a logical group inside the cluster:

| Namespace | Holds |
|---|---|
| `default` | Your resources, when you don't choose a namespace |
| `kube-system` | Kubernetes' own components |
| `kube-flannel` | The Flannel CNI |
| `kube-public`, `kube-node-lease` | Cluster info and node heartbeats |

Not every resource lives in a namespace:

| Namespaced | Cluster-wide |
|---|---|
| Pods, Deployments, Services, ConfigMaps, Secrets | Nodes, Namespaces, PersistentVolumes |

A Pod always belongs to a namespace. A Node belongs to the whole cluster. `kubectl api-resources` shows this in the `NAMESPACED` column.

---

## 6. The Pod network, in short

When a Pod is created:

1. containerd creates a **network namespace** for the Pod.
2. The CNI (Flannel, using the `bridge` plugin) creates a **veth pair** — a virtual cable with two ends:
   - one end goes inside the Pod and is called `eth0`,
   - the other end stays on the node (`vethXXXX`) and is plugged into the bridge **`cni0`**.
3. The Pod gets an IP from the node's slice of the Pod range.

```text
 ┌── Pod A ─────────┐   ┌── Pod B ─────────┐
 │ eth0 10.244.0.5  │   │ eth0 10.244.0.6  │
 └────────┬─────────┘   └────────┬─────────┘
       vethaaaa              vethbbbb
          └──────────┬───────────┘
              cni0  10.244.0.1   (bridge, Pods' gateway)
                     │
              node routing ──► flannel.1 (VXLAN) ──► Pods on other nodes
```

- Pod range: `10.244.0.0/16`. Each node gets its own `/24` slice (ours: `10.244.0.0/24`).
- **One veth per Pod**, not per container. Containers in a Pod share one IP.
- Pods with `hostNetwork: true` (the control plane, kube-proxy, Flannel) skip all this and use the node IP directly.
- It is all regular Linux networking: interfaces, a bridge and routes.

---

## Summary

- The install prepared Linux (swap, modules, sysctl), added a runtime (containerd), built the control plane (`kubeadm init`) and a network (Flannel).
- Everything talks to the **API server**; only the API server talks to **etcd**.
- kubelet and containerd are **systemd services**; the control plane is **static Pods**; everything else is **regular Pods**.
- `kubectl` sees the cluster; `crictl` sees one node's containers.
- Resources are either **namespaced** or **cluster-wide**.
- Each Pod is wired to `cni0` with a **veth pair**.

### Check yourself

1. Why is the kubelet not a Pod?
2. You delete `kube-apiserver-k8s-lab` with `kubectl`. What happens, and why?
3. Why must the node IP never change after `kubeadm init`?
4. A Pod has two containers. How many IPs and how many veth pairs does it get?
5. Is a Namespace itself namespaced?

---

## Exercises

Find each component on your VM: [exercises/](exercises/README.md)

---

## Further reading

- [Cluster components](https://kubernetes.io/docs/concepts/overview/components/)
- [Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
- [Container runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)
- [Static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)
- [Cluster networking](https://kubernetes.io/docs/concepts/cluster-administration/networking/)
