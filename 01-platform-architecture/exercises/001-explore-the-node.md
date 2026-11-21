# Exercise 001 — Explore the Node

**Chapter:** 01 Platform Architecture | **Time:** ~10 min

## Goal

Find out everything Kubernetes knows about your node: its role, resources, OS, runtime and health.

## Tasks

**1.** List the nodes with extra details:

```bash
kubectl get nodes -o wide
```

**2.** Describe the node (replace `k8s-lab` with your node name):

```bash
kubectl describe node k8s-lab
```

The output is long. Look for these sections: `Roles`, `Labels`, `Taints`, `Conditions`, `Addresses`, `Capacity`, `Allocatable`, `System Info`, `Non-terminated Pods`, `Allocated resources`.

**3.** Compare with what Linux says:

```bash
nproc
free -h
hostname
ip -4 addr show
```

## Questions

1. What is the node's **role**?
2. What is its **INTERNAL-IP**? Is it the same IP you gave the VM in the static IP step?
3. Which **container runtime** and version does it use?
4. How many CPUs and how much memory does Kubernetes see (`Capacity`)? Does it match `nproc` and `free -h`?
5. In `Conditions`, which condition must be `True` for the node to accept Pods? What are the other conditions checking?
6. Under `Taints` — what does it say? Why?
7. How many Pods are running on the node right now (`Non-terminated Pods`)?

<details>
<summary>Solution</summary>

1. `control-plane`.
2. The static IP, e.g. `172.16.71.10`. kubeadm used it as `--apiserver-advertise-address`.
3. `containerd://<version>` (e.g. `2.2.2`).
4. `Capacity` matches the VM: CPUs = `nproc`, memory ≈ `free -h` total. `Allocatable` is a bit lower — memory reserved for the system.
5. `Ready` must be `True`. The others (`MemoryPressure`, `DiskPressure`, `PIDPressure`, `NetworkUnavailable`) should be `False` — they warn when the node is running out of memory, disk or process IDs, or has no Pod network.
6. `<none>` — we removed the `node-role.kubernetes.io/control-plane:NoSchedule` taint during installation so apps can run on our single node.
7. About 8: etcd, kube-apiserver, kube-controller-manager, kube-scheduler, kube-proxy, 2× coredns, kube-flannel.

</details>

## Cleanup

Nothing to clean up.
