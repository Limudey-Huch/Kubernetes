# 01 — Platform Architecture

Install a single-node Kubernetes cluster with kubeadm, then take a short tour of the components that make it work.

**Before you start:** your VM must meet [../vm-requirements.md](../vm-requirements.md). Take a VM snapshot first.

---

## Goals

By the end of this chapter you can:

- Install Kubernetes on Ubuntu with kubeadm, step by step.
- Name the main cluster components and see each one running on your VM.
- Explain the difference between `kubectl` and `crictl`.
- Tell namespaced resources from cluster-wide resources.

---

## Part 1 — Install the cluster

We install in this order:

```text
1. Prepare Ubuntu        (swap off, kernel modules, sysctl)
2. Container runtime     (containerd)
3. Kubernetes packages   (kubeadm, kubelet, kubectl)
4. Create the cluster    (kubeadm init)
5. Pod network           (Flannel CNI)
6. Allow workloads       (remove control-plane taint — single node only)
```

> All commands run **inside the VM**.

> **Shortcut:** the same steps are automated in the course scripts — see [../installation-guide.md](../installation-guide.md). Do the manual install below at least once to understand each step; use the scripts to reinstall quickly.

### Step 1 — Prepare Ubuntu

**1.1 Disable swap** (now and after reboot):

```bash
sudo swapoff -a
sudo sed -i '/\sswap\s/ s/^/#/' /etc/fstab
swapon --show        # no output = swap is off
```

Why: the kubelet calculates memory for Pods assuming there is no swap.

**1.2 Load kernel modules:**

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

- `overlay` — the filesystem containerd uses for image layers.
- `br_netfilter` — lets iptables see traffic that crosses the Linux bridge (Pod traffic).

**1.3 Kernel network settings:**

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
sysctl net.ipv4.ip_forward     # expect: = 1
```

`ip_forward = 1` lets the node route packets between Pods and the outside world.

### Step 2 — Install containerd (the container runtime)

Kubernetes does not run containers itself. It asks a **container runtime** to do it, through the **CRI** (Container Runtime Interface). We use **containerd**.

```bash
sudo apt-get update
sudo apt-get install -y containerd

# Generate the default config and switch to the systemd cgroup driver
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd
systemctl is-active containerd     # expect: active
```

Why `SystemdCgroup = true`: Ubuntu uses systemd to manage cgroups (CPU/RAM limits). kubelet and containerd must use the **same** cgroup driver, otherwise Pods restart randomly.

```bash
grep SystemdCgroup /etc/containerd/config.toml    # expect: SystemdCgroup = true
```

### Step 3 — Install kubeadm, kubelet and kubectl

| Package | What it is |
|---|---|
| `kubeadm` | Tool that **builds** the cluster (certificates, config, control-plane) |
| `kubelet` | The node agent — runs as a systemd service on every node |
| `kubectl` | The CLI we use to talk to the cluster |

```bash
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Kubernetes package repository (version 1.36)
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl cri-tools
sudo apt-mark hold kubelet kubeadm kubectl     # prevent accidental upgrades

sudo systemctl enable kubelet
```

`apt-mark hold` matters: Kubernetes upgrades must be done in a controlled order, never by a random `apt upgrade`.

`cri-tools` provides `crictl`, a debugging CLI for the container runtime (it is no longer installed automatically with kubeadm). Point it at containerd:

```bash
cat <<EOF | sudo tee /etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
EOF
```

> 📸 **Snapshot now** — "Prerequisites done". If `kubeadm init` goes wrong you can come back here.

### Step 4 — Create the cluster

Find your VM's static IP:

```bash
ip -4 addr show
# use the cluster-facing IP, e.g. 192.168.149.133
```

Initialize the control plane:

```bash
sudo kubeadm init \
  --apiserver-advertise-address=<YOUR-VM-IP> \
  --pod-network-cidr=10.244.0.0/16
```

| Flag | Meaning |
|---|---|
| `--apiserver-advertise-address` | The IP the API server listens on and puts in its certificate |
| `--pod-network-cidr` | The IP range for Pods. `10.244.0.0/16` is what Flannel expects |

This takes 1–3 minutes. kubeadm prints its phases (`[preflight]`, `[certs]`, `[kubeconfig]`, `[control-plane]`, `[etcd]` ...) and ends with:

```text
Your Kubernetes control-plane has initialized successfully!
```

Give your user access to the cluster (`kubectl` reads `~/.kube/config`):

```bash
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

Check:

```bash
kubectl get nodes
```

```text
NAME         STATUS     ROLES           AGE   VERSION
k8s-lab      NotReady   control-plane   40s   v1.36.x
```

`NotReady` is expected — there is **no Pod network yet**.

### Step 5 — Install the Pod network (Flannel)

Kubernetes defines **CNI** (Container Network Interface) but does not ship a network. We install **Flannel**, a simple CNI that gives each Pod an IP from `10.244.0.0/16`.

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

Wait for the node to become Ready:

```bash
kubectl wait --for=condition=Ready node --all --timeout=180s
kubectl get nodes
```

```text
NAME         STATUS   ROLES           AGE   VERSION
k8s-lab      Ready    control-plane   2m    v1.36.x
```

### Step 6 — Allow workloads on the control-plane node

By default the control-plane node has a **taint** that blocks regular Pods from running on it (in production, apps run on worker nodes). We have only one node, so we remove it:

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

The `-` at the end means "remove".

### Step 7 — Smoke test

```bash
kubectl create deployment hello --image=nginx
kubectl get pods -o wide
```

```text
NAME                     READY   STATUS    RESTARTS   AGE   IP           NODE
hello-6d4bc4d5fb-lxvwn   1/1     Running   0          20s   10.244.0.4   k8s-lab
```

A Pod is `Running` with an IP from `10.244.0.0/16` — the cluster works.

> 📸 **Snapshot now** — "Cluster ready".

---

## Part 2 — Tour of the platform

Now let's find each component from [00-introduction](../00-introduction/00-introduction.md) on our VM.

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

### 2.1 Who runs the containers? — containerd and crictl

```bash
sudo crictl ps
```

```text
CONTAINER   IMAGE   CREATED   STATE     NAME                      POD
...                           Running   nginx                     hello-...
...                           Running   coredns                   coredns-...
...                           Running   kube-flannel              kube-flannel-ds-...
...                           Running   kube-proxy                kube-proxy-...
...                           Running   kube-scheduler            kube-scheduler-k8s-lab
...                           Running   kube-controller-manager   kube-controller-manager-k8s-lab
...                           Running   kube-apiserver            kube-apiserver-k8s-lab
...                           Running   etcd                      etcd-k8s-lab
```

What we see:

- **containerd** runs every container — our app *and* Kubernetes' own components.
- `crictl` is a debugging CLI that talks **directly to the runtime** (like `docker ps`, but for CRI).
- We do **not** use `docker` here — Kubernetes does not need Docker at all.

| Tool | Talks to | Use it for |
|---|---|---|
| `kubectl` | kube-apiserver | Everything, day to day |
| `crictl` | containerd (on this node only) | Low-level debugging on a node |

### 2.2 The front door — kube-apiserver

```bash
kubectl cluster-info
```

```text
Kubernetes control plane is running at https://192.168.149.133:6443
CoreDNS is running at https://192.168.149.133:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

```bash
sudo ss -ltnp | grep 6443
```

```text
LISTEN 0  4096  *:6443  *:*  users:(("kube-apiserver",pid=...))
```

- `kubectl` only ever talks to the **API server**, on port **6443**, over **HTTPS**.
- Every action in Kubernetes starts with a request to the API server.
- `kubectl` finds the address and its credentials in `~/.kube/config`:

```bash
grep server ~/.kube/config
```

### 2.3 Where do the control-plane components come from? — static Pods

The control-plane components run as Pods, but who starts them before there is an API server? The **kubelet** does, from files on disk:

```bash
ls /etc/kubernetes/manifests/
```

```text
etcd.yaml  kube-apiserver.yaml  kube-controller-manager.yaml  kube-scheduler.yaml
```

These are **static Pods**: the kubelet watches this folder and runs whatever is in it. kubeadm wrote these files during `kubeadm init`.

### 2.4 The node agent — kubelet

The kubelet is the only Kubernetes component that is **not** a container. It is a regular systemd service:

```bash
systemctl status kubelet --no-pager | head -5
```

```text
● kubelet.service - kubelet: The Kubernetes Node Agent
     Active: active (running)
```

If the kubelet stops, the node becomes `NotReady` and nothing on it is managed.

### 2.5 The cluster database — etcd

```bash
sudo ls /var/lib/etcd/member/
```

```text
snap  wal
```

- **etcd** stores the full desired state of the cluster (every Deployment, Service, Secret ...).
- Only the API server talks to etcd.
- Losing etcd without a backup = losing the cluster.

### 2.6 The node

```bash
kubectl get nodes -o wide
```

```text
NAME      STATUS   ROLES           VERSION   INTERNAL-IP       OS-IMAGE             CONTAINER-RUNTIME
k8s-lab   Ready    control-plane   v1.36.x   192.168.149.133   Ubuntu 24.04.x LTS   containerd://1.7.x   (2.x on Ubuntu 26.04)
```

- Our cluster has one **Node**, with the role **control-plane** (and, after removing the taint, it runs apps too).
- `INTERNAL-IP` is the static IP we gave `kubeadm init`.
- `CONTAINER-RUNTIME` confirms containerd.

### 2.7 Pods and Namespaces

```bash
kubectl get pods -A
```

```text
NAMESPACE      NAME                              READY   STATUS
default        hello-6d4bc4d5fb-lxvwn            1/1     Running
kube-flannel   kube-flannel-ds-bxgqg             1/1     Running
kube-system    coredns-...                       1/1     Running
kube-system    etcd-k8s-lab                      1/1     Running
kube-system    kube-apiserver-k8s-lab            1/1     Running
kube-system    kube-controller-manager-k8s-lab   1/1     Running
kube-system    kube-proxy-...                    1/1     Running
kube-system    kube-scheduler-k8s-lab            1/1     Running
```

```bash
kubectl get namespaces
```

```text
NAME              STATUS
default           Active
kube-flannel      Active
kube-node-lease   Active
kube-public       Active
kube-system       Active
```

- A **Namespace** is a logical group inside the cluster.
- `kube-system` holds Kubernetes' own components; `default` is where our resources go if we don't choose a namespace.
- `-A` means "all namespaces".

### 2.8 Namespaced vs cluster-wide resources

```bash
kubectl api-resources | head -20
```

Look at the `NAMESPACED` column:

| Namespaced (`true`) | Cluster-wide (`false`) |
|---|---|
| Pods, Deployments, Services, ConfigMaps, Secrets | Nodes, Namespaces, PersistentVolumes |

A Pod always lives in a namespace. A Node belongs to the whole cluster.

### 2.9 The Pod network on the host

```bash
ip -4 addr show cni0
ip route | grep 10.244
```

```text
cni0: ... inet 10.244.0.1/24
10.244.0.0/24 dev cni0 proto kernel scope link src 10.244.0.1
```

- Flannel created a Linux bridge, `cni0`, as the gateway for Pods on this node.
- Each node gets its own slice (`10.244.0.0/24`) of the Pod range (`10.244.0.0/16`).
- Pod networking is regular Linux networking — interfaces and routes.

---

## Summary

| Component | Where it runs on our VM | How we saw it |
|---|---|---|
| kube-apiserver | static Pod | `kubectl cluster-info`, `ss -ltnp \| grep 6443` |
| etcd | static Pod | `/var/lib/etcd` |
| scheduler / controller-manager | static Pods | `/etc/kubernetes/manifests` |
| kubelet | systemd service | `systemctl status kubelet` |
| containerd | systemd service | `sudo crictl ps` |
| kube-proxy, CoreDNS | Pods in `kube-system` | `kubectl get pods -A` |
| Flannel (CNI) | Pod in `kube-flannel` | `cni0`, `ip route` |

Key ideas:

- `kubectl` → API server is the **only** way we manage the cluster.
- Kubernetes runs its own control plane **as Pods**, started by the kubelet from static manifests.
- containerd runs all containers; `crictl` is for node-level debugging.
- Resources are either **namespaced** or **cluster-wide**.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `kubeadm init` fails on `[preflight]` swap | Swap still on | `sudo swapoff -a`, fix `/etc/fstab` |
| Preflight: `bridge-nf-call-iptables` / `ip_forward` | sysctl not applied | Repeat Step 1.3 |
| Node stays `NotReady` | No CNI, or Flannel not running | `kubectl get pods -n kube-flannel` |
| Pods keep restarting, control plane unstable | cgroup driver mismatch | Check `SystemdCgroup = true`, restart containerd |
| `kubectl`: `connection refused ... :6443` | API server down, or no kubeconfig | `sudo crictl ps \| grep apiserver`, check `~/.kube/config` |
| Cluster broken after reboot | VM IP changed | Use a static IP (see vm-requirements) |

Start over (if needed):

```bash
sudo kubeadm reset -f
sudo rm -rf $HOME/.kube /etc/cni/net.d
# then repeat from Step 4 (or restore the "Prerequisites done" snapshot)
```

---

## Exercises

In-class exploration exercises for this chapter: [exercises/](exercises/README.md)

---

## Further reading

- [Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
- [Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
- [Container runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)
- [Static Pods](https://kubernetes.io/docs/tasks/configure-pod-container/static-pod/)
