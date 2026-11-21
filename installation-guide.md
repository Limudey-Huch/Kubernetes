# Installation Guide — Lab VM Setup with Scripts

Step-by-step guide for a new student: take your Ubuntu VM from "just installed" to a **working single-node Kubernetes cluster**, using the course scripts.

**Assumption:** your VM already meets the hardware requirements in [vm-requirements.md](vm-requirements.md) and has **Ubuntu Server** installed, with a user that has `sudo`.

---

## Overview

```text
 Step 0   Connect to the VM over SSH
 Step 1   Snapshot: "clean-os"
 Step 2   Clone the course repository (guides + scripts)
 Step 3   01-reset-vm.sh      → remove anything that conflicts with Kubernetes
 Step 4   03-static-ip.sh     → give the VM a fixed IP + hostname
 Step 5   Snapshot: "static-ip"
 Step 6   02-install-k8s.sh   → install Kubernetes (kubeadm + containerd + Flannel)
 Step 7   Verify the cluster
 Step 8   Snapshot: "cluster-ready"
```

> ⚠️ **Run order is 01 → 03 → 02.** The static IP must be set **before** Kubernetes is installed, because `kubeadm init` writes the node IP into the cluster certificates.

| Script | What it does | Changes the VM? |
|---|---|---|
| `01-reset-vm.sh` | Removes Docker, containerd, old Kubernetes, Jenkins and similar services, swap | Only with `--yes` |
| `03-static-ip.sh` | Sets a static IP and hostname, with auto-rollback if you lose the connection | Only with `--yes` |
| `02-install-k8s.sh` | Installs and starts a single-node Kubernetes cluster | Only with `--yes` |

Every script runs in **dry-run mode by default**: it only shows what it *would* do. Always run it once without `--yes`, read the output, then run it again with `--yes`.

All commands below run **inside the VM** unless marked **(host)**.

---

## Step 0 — Connect to the VM over SSH

Working over SSH lets you copy and paste commands, which the VM console usually does not.

**0.1 In the VM console**, log in and find the VM's IP address:

```bash
ip -4 addr show
```

Look for the main interface (`ens33`, `enp2s0`, `enp0s3` ...) and its address, e.g. `172.16.71.139/24`.

**0.2 Make sure SSH is installed and running:**

```bash
sudo apt-get update
sudo apt-get install -y openssh-server
sudo systemctl enable --now ssh
```

**0.3 (host)** From your computer's terminal (macOS Terminal / Windows PowerShell):

```bash
ssh <your-vm-user>@<vm-ip>
```

Example: `ssh student@172.16.71.139`. Type `yes` the first time, then your VM password.

---

## Step 1 — Snapshot: "clean-os"

In your hypervisor (VMware / VirtualBox / UTM / Parallels), take a snapshot of the VM and name it **`clean-os`**.

If anything goes wrong later, you can always return to this point.

---

## Step 2 — Clone the course repository

All the guides and scripts are in the course Git repository. Clone it into your home folder **on the VM**:

```bash
sudo apt-get install -y git
cd ~
git clone <course-repo-url> kubernetes-iccp
```

> Your instructor gives you `<course-repo-url>`.

The repository layout:

```text
~/kubernetes-iccp/
├── installation-guide.md          ← this guide
├── vm-requirements.md
├── 00-introduction/
├── 01-platform-architecture/
├── 02-reconciliation-loop/
├── ...
└── scripts/
    ├── 01-reset-vm.sh
    ├── 02-install-k8s.sh
    └── 03-static-ip.sh
```

Go to the scripts folder and make sure the scripts are executable:

```bash
cd ~/kubernetes-iccp/scripts
chmod +x *.sh
ls -l
```

You should see `-rwx` at the start of each line.

> 📁 **All script commands in this guide run from `~/kubernetes-iccp/scripts`.** After every reboot or new SSH connection, go back there first:
>
> ```bash
> cd ~/kubernetes-iccp/scripts
> ```

**Getting updates:** when the instructor publishes new chapters or script fixes:

```bash
cd ~/kubernetes-iccp
git pull
```

---

## Step 3 — Clean the VM: `01-reset-vm.sh`

This removes anything that would conflict with a clean Kubernetes install: Docker and its containerd, any older Kubernetes, extra services (Jenkins, Apache, Nginx, MySQL, PostgreSQL), leftover network interfaces and iptables rules, and swap.

It does **not** touch SSH, networking, DNS, users or your files.

> On a freshly installed Ubuntu there may be nothing to remove — the script will just say so. Run it anyway; it also turns off swap.

**3.1 Dry run — see what would be removed:**

```bash
cd ~/kubernetes-iccp/scripts
./01-reset-vm.sh
```

Example output:

```text
MODE: DRY RUN — nothing will change. Run with --yes to apply.

==> 2. Extra services (jenkins apache2 nginx mysql postgresql)
   [would] stop + disable jenkins
   [would] purge jenkins
==> 3. Docker / containerd
   found: 4 containers, 2 images, 13 volumes
   [would] remove all containers, images, volumes, networks
   ...
```

Read the list. ⚠️ **Docker containers, images and volumes will be deleted.** If you have anything you need in Docker, back it up first.

**3.2 Apply:**

```bash
./01-reset-vm.sh --yes
```

Enter your password if `sudo` asks. At the end you get a list of the services still running and the open ports — expect only SSH (`:22`) and local DNS (`127.0.0.53:53`).

**3.3 Reboot:**

```bash
sudo reboot
```

Wait ~30 seconds and reconnect:

```bash
ssh <your-vm-user>@<vm-ip>
cd ~/kubernetes-iccp/scripts
```

---

## Step 4 — Static IP and hostname: `03-static-ip.sh`

### 4.1 Choose an IP address

The IP must be:

- In the **same network** as your current IP (same first three numbers for a `/24`).
- **Outside the DHCP range** of your virtual network, so no other VM ever gets it.
- **Not used** by another machine (the script checks this with ping).

| Hypervisor network | DHCP range (typical) | Safe static IPs |
|---|---|---|
| VMware NAT (Fusion / Workstation) | `x.x.x.128` – `x.x.x.254` | `x.x.x.3` – `x.x.x.127`, e.g. **`x.x.x.10`** |
| VirtualBox NAT Network | `x.x.x.3` – `x.x.x.254` (configurable) | Use Bridged or Host-Only and pick outside the router's DHCP range |
| Bridged to home / office network | Set by your router | Ask the network owner, or use a DHCP reservation in the router |

Example: current IP `172.16.71.139/24`, VMware NAT → choose **`172.16.71.10/24`**.

### 4.2 Dry run

```bash
./03-static-ip.sh --ip 172.16.71.10/24 --hostname k8s-lab
```

Replace the IP with your own choice. The script detects the interface, gateway and DNS by itself and prints the netplan config it would write:

```text
==> 1. Current network
   Interface : enp2s0
   Current IP: 172.16.71.139/24   dynamic: yes (DHCP)
   Gateway   : 172.16.71.2
   Hostname  : ubuntu

==> 2. Checks
   OK  172.16.71.10 is free (no ping reply).
   !!  The IP will change: your SSH session will drop. Reconnect to 172.16.71.10.
   OK  Gateway 172.16.71.2 reachable.
```

Check that the interface and gateway look right. If detection is wrong, add `--iface <name>` and/or `--gw <ip>`.

### 4.3 Apply

```bash
./03-static-ip.sh --ip 172.16.71.10/24 --hostname k8s-lab --yes
```

Your SSH session **will freeze or disconnect** — that is expected, the IP just changed.

### 4.4 Reconnect and confirm — within 3 minutes ⏱️

The script armed an **auto-rollback**: if you don't confirm within 3 minutes, the old network config comes back by itself (so you can never lock yourself out).

**(host)** Close the frozen terminal (or press `Enter`, then type `~.`) and connect to the **new** IP:

```bash
ssh <your-vm-user>@172.16.71.10
```

Then confirm:

```bash
cd ~/kubernetes-iccp/scripts
./03-static-ip.sh --confirm
```

```text
==> Confirming new network config
   OK  Auto-rollback cancelled. The static IP is permanent.
   enp2s0 172.16.71.10/24
```

> If the 3 minutes passed before you confirmed, the VM went back to its old IP. Connect to the old IP and repeat 4.3–4.4.

### 4.5 Check

```bash
hostname                              # k8s-lab
ip -4 addr show                       # your new IP, without the word "dynamic"
ping -c 2 registry.k8s.io             # internet + DNS work
```

Reboot once to prove the IP survives a restart:

```bash
sudo reboot
```

```bash
ssh <your-vm-user>@172.16.71.10
ip -4 addr show
```

---

## Step 5 — Snapshot: "static-ip"

Take a snapshot named **`static-ip`**. This is the best point to return to if you ever want to reinstall Kubernetes from scratch.

---

## Step 6 — Install Kubernetes: `02-install-k8s.sh`

This performs the same 7 steps as Part 1 of [chapter 01](01-platform-architecture/01-platform-architecture.md): prepare Ubuntu, install containerd, install kubeadm/kubelet/kubectl, `kubeadm init`, Flannel, remove the control-plane taint, and a smoke test.

### 6.1 Dry run — preflight checks

```bash
cd ~/kubernetes-iccp/scripts
./02-install-k8s.sh
```

```text
==> Preflight checks
   OK    OS: Ubuntu 26.04 LTS (arm64)
   OK    CPU: 4
   OK    RAM: 7.2 GB
   OK    Free disk: 49 GB
   OK    Node IP: 172.16.71.10 on enp2s0 (static)
   OK    Hostname: k8s-lab
   OK    Swap is off
   OK    No Docker / containerd.io
   OK    Kubernetes ports checked
   OK    Kubernetes v1.36 repo reachable
```

Every line must be `OK` (a `WARN` is allowed, a `FAIL` is not). Common failures:

| FAIL / WARN | Fix |
|---|---|
| `Node IP ... is DHCP` | Go back to Step 4 |
| `Docker / containerd.io found` | Go back to Step 3 |
| `Port ... already in use` | Something is already running — Step 3, or see "Start over" below |
| `Cannot reach Kubernetes repo` | No internet from the VM: `ping -c 2 8.8.8.8` |

### 6.2 Install

```bash
./02-install-k8s.sh --yes
```

Takes about **2–5 minutes**. Each step prints one `OK` line; the full log is saved in `/tmp/k8s-install-<date>.log`.

The end of the output should look like this:

```text
==> 7. Smoke test
   OK    nginx Pod Running with IP 10.244.0.4
   OK    HTTP to Pod works

==> Cluster
NAME      STATUS   ROLES           AGE   VERSION   INTERNAL-IP    ...   CONTAINER-RUNTIME
k8s-lab   Ready    control-plane   56s   v1.36.6   172.16.71.10   ...   containerd://2.2.2

Done. Warnings: 0   Log: /tmp/k8s-install-20261121-164800.log
```

---

## Step 7 — Verify the cluster

```bash
kubectl get nodes
```

```text
NAME      STATUS   ROLES           AGE   VERSION
k8s-lab   Ready    control-plane   2m    v1.36.6
```

```bash
kubectl get pods -A
```

All Pods should be `Running`:

```text
NAMESPACE      NAME                              READY   STATUS
kube-flannel   kube-flannel-ds-f8wlx             1/1     Running
kube-system    coredns-589f44dc88-9h9b9          1/1     Running
kube-system    coredns-589f44dc88-mcgcm          1/1     Running
kube-system    etcd-k8s-lab                      1/1     Running
kube-system    kube-apiserver-k8s-lab            1/1     Running
kube-system    kube-controller-manager-k8s-lab   1/1     Running
kube-system    kube-proxy-pbth9                  1/1     Running
kube-system    kube-scheduler-k8s-lab            1/1     Running
```

```bash
sudo crictl ps | head -5
```

Reboot once and check that the cluster comes back on its own:

```bash
sudo reboot
```

```bash
ssh <your-vm-user>@172.16.71.10
kubectl get nodes
kubectl get pods -A
```

> Right after a reboot, CoreDNS may show `Unknown` or `ContainerCreating` for up to a minute. That is normal — wait and check again.
>
> The `RESTARTS` column goes up by 1 for every Pod after each reboot, and control-plane Pods may show 1–2 restarts right after installation. That is normal. A problem is a number that **keeps growing** while the VM is running — check with `kubectl get pods -A` a few minutes apart.

---

## Step 8 — Snapshot: "cluster-ready"

Take a snapshot named **`cluster-ready`**. Every lab in the course starts from here.

You are ready for [chapter 01 — Part 2: Tour of the platform](01-platform-architecture/01-platform-architecture.md#part-2--tour-of-the-platform).

---

## Start over / clean everything

### Option 1 — Revert a snapshot (fastest)

| Revert to | When |
|---|---|
| `cluster-ready` | A lab broke the cluster |
| `static-ip` | You want to reinstall Kubernetes from scratch |
| `clean-os` | You want to redo everything, including the network |

### Option 2 — Wipe and reinstall with the scripts

`01-reset-vm.sh` also removes Kubernetes completely (`kubeadm reset`, packages, `/etc/kubernetes`, etcd data, CNI config, `~/.kube`). The static IP is **kept**.

```bash
cd ~/kubernetes-iccp/scripts
./01-reset-vm.sh --yes
sudo reboot
```

Reconnect, then:

```bash
cd ~/kubernetes-iccp/scripts
./02-install-k8s.sh --yes
```

---

## Troubleshooting

| Problem | What to do |
|---|---|
| `Permission denied` when running a script | `cd ~/kubernetes-iccp/scripts && chmod +x *.sh` |
| `No such file or directory` for `./0X-...sh` | You are not in the scripts folder: `cd ~/kubernetes-iccp/scripts` |
| `git clone` asks for a username/password | The repo is private — ask the instructor for access |
| `This script needs sudo` | Your user is not in the sudo group — ask the instructor |
| SSH froze after `03-static-ip.sh --yes` | Expected. Reconnect to the **new** IP and run `--confirm` within 3 minutes |
| Lost the VM after the IP change | Wait 3 minutes (auto-rollback), then SSH to the old IP. Or use the VM console |
| `kubeadm init failed` | The script prints the last 30 log lines. Fix the cause, then: `./01-reset-vm.sh --yes`, reboot, `./02-install-k8s.sh --yes` |
| Node `NotReady` | `kubectl get pods -n kube-flannel` — Flannel must be `Running` |
| `kubectl: connection refused ... :6443` | API server is still starting after a reboot — wait 1 minute. If it persists: `sudo crictl ps \| grep apiserver` |
| Cluster broken after reboot, IP changed | The static IP was not confirmed. Redo Step 4, then reinstall (Option 2 above) |

---

**Tested on:** Ubuntu 26.04 LTS (arm64) on VMware Fusion, 4 vCPU / 8 GB RAM, Kubernetes 1.36.6, containerd 2.2.2, Flannel.
