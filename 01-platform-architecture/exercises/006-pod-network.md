# Exercise 006 — The Pod Network

**Chapter:** 01 Platform Architecture | **Time:** ~15 min

## Goal

See how Pods get IP addresses and how they reach each other — and how that shows up in Linux networking on the node.

## Tasks

**1.** Look at the node's network before creating Pods:

```bash
ip -4 addr show cni0
ip route | grep 10.244
ip -o link | grep -c veth
```

**2.** Create two Pods:

```bash
kubectl run web1 --image=nginx
kubectl run web2 --image=nginx
kubectl get pods -o wide
```

**3.** Count the virtual interfaces again:

```bash
ip -o link | grep -c veth
```

**4.** Reach a Pod from the node:

```bash
WEB2_IP=$(kubectl get pod web2 -o jsonpath='{.status.podIP}')
echo $WEB2_IP
curl -s $WEB2_IP | grep title
```

**5.** Reach a Pod from another Pod:

```bash
kubectl exec web1 -- curl -s $WEB2_IP | grep title
```

**6.** Delete `web2` and create it again. Check its IP:

```bash
kubectl delete pod web2
kubectl run web2 --image=nginx
kubectl get pods -o wide
```

## Questions

1. Which subnet do the Pod IPs come from? Where was this range set?
2. What is `cni0`? What is its IP, and what role does it play for the Pods?
3. How many `veth` interfaces were added when you created two Pods? What is each one?
4. Could the node reach the Pod IP directly? Could one Pod reach another? Was there any NAT or port mapping, like `docker run -p`?
5. After recreating `web2`, did it keep the same IP? What does that mean for apps that want to talk to `web2`?

<details>
<summary>Solution</summary>

1. `10.244.0.0/24` — this node's slice of the `10.244.0.0/16` range we passed to `kubeadm init --pod-network-cidr`.
2. A Linux bridge created by Flannel. Its IP (`10.244.0.1`) is the **gateway** for all Pods on this node.
3. Two — one per Pod. Each `veth` pair is a virtual cable: one end inside the Pod (`eth0`), the other end plugged into `cni0` on the node.
4. Yes and yes, directly by IP, with no NAT and no port mapping. This is a core Kubernetes rule: every Pod gets its own IP and can reach every other Pod.
5. Usually **not** — a new Pod gets a new IP. Pod IPs are not stable, so apps should not depend on them. Kubernetes solves this with **Services** (a later chapter).

</details>

## Cleanup

```bash
kubectl delete pod web1 web2
```
