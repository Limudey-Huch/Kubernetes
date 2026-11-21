# Exercise 002 — Find the Control Plane

**Chapter:** 01 Platform Architecture | **Time:** ~15 min

## Goal

Locate every control-plane component on your VM: as a Pod, as a file on disk, and as a process listening on a port.

## Tasks

**1.** List the Pods in `kube-system`:

```bash
kubectl get pods -n kube-system -o wide
```

**2.** Find the files the kubelet uses to start the control plane:

```bash
ls -l /etc/kubernetes/manifests/
```

**3.** Which image and version does each component use?

```bash
sudo grep -h "image:" /etc/kubernetes/manifests/*.yaml
```

**4.** Which ports does each component listen on?

```bash
sudo ss -ltnp | grep -E 'kube|etcd'
```

**5.** Fill in this table:

| Component | Runs as (Pod / systemd service) | Port(s) | Listens on (all interfaces / localhost / node IP) |
|---|---|---|---|
| kube-apiserver | | | |
| etcd | | | |
| kube-scheduler | | | |
| kube-controller-manager | | | |
| kubelet | | | |

**6.** Ask the API server about its own health:

```bash
kubectl get --raw='/readyz?verbose' | tail -5
```

## Questions

1. Which control-plane component is **not** a Pod? How is it started?
2. Why do the scheduler and controller-manager listen only on `127.0.0.1`?
3. etcd listens on two ports. What is the difference between them?
4. Which port does `kubectl` use? Where does `kubectl` find that address?
5. What would happen if you deleted `/etc/kubernetes/manifests/kube-apiserver.yaml`? (Don't do it — just think.)

<details>
<summary>Solution</summary>

Table:

| Component | Runs as | Port(s) | Listens on |
|---|---|---|---|
| kube-apiserver | static Pod | 6443 | all interfaces (`*`) |
| etcd | static Pod | 2379, 2380 | localhost + node IP |
| kube-scheduler | static Pod | 10259 | localhost |
| kube-controller-manager | static Pod | 10257 | localhost |
| kubelet | systemd service | 10250 | all interfaces |

1. The **kubelet**. It is a systemd service (`systemctl status kubelet`). It has to run first, because it is the one that starts the static Pods.
2. Only the API server needs to reach them from outside. They talk *to* the API server; nobody needs to talk to them over the network, so they don't expose themselves.
3. `2379` — client port (the API server talks to etcd here). `2380` — peer port, used between etcd members in a multi-node control plane.
4. `6443` (HTTPS). The address is in `~/.kube/config` under `server:`.
5. The kubelet would stop the API server. `kubectl` would stop working (`connection refused`), even though etcd and the rest are still running. Putting the file back brings it back.

</details>

## Cleanup

Nothing to clean up.
