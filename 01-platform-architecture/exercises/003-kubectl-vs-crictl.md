# Exercise 003 — kubectl vs crictl

**Chapter:** 01 Platform Architecture | **Time:** ~15 min

## Goal

See the same workload from two levels: the Kubernetes API (`kubectl`) and the container runtime (`crictl`). Then kill a container behind Kubernetes' back and watch it come back.

## Tasks

**1.** Start a Pod:

```bash
kubectl run web --image=nginx
kubectl get pod web -o wide
```

**2.** Find the same Pod in the runtime:

```bash
sudo crictl pods --name web
sudo crictl ps --name web
sudo crictl images | grep nginx
```

**3.** Compare counts:

```bash
kubectl get pods -A --no-headers | wc -l
sudo crictl pods -q | wc -l
sudo crictl ps -q | wc -l
```

**4.** Kill the container directly in the runtime. Open a second terminal and run:

```bash
watch -n1 kubectl get pod web
```

In the first terminal:

```bash
POD_ID=$(sudo crictl pods --name '^web$' -q)
CONTAINER_ID=$(sudo crictl ps --pod $POD_ID -q)
sudo crictl stop $CONTAINER_ID
```

Watch the `RESTARTS` column in the second terminal.

**5.** Look at all containers of the Pod, including stopped ones:

```bash
sudo crictl ps -a --pod $POD_ID
```

## Questions

1. Does `crictl` show namespaces? Pods? Deployments? Services?
2. `crictl pods` and `crictl ps` — what is the difference between a *pod sandbox* and a *container*?
3. In task 3, are the numbers the same? Why might `crictl pods` show more than `kubectl get pods -A`?
4. After you stopped the container in task 4 — who restarted it? Was it the same container or a new one?
5. Which tool would you use to: (a) deploy an app, (b) check if containerd itself can pull an image, (c) debug a node where the API server is down?

<details>
<summary>Solution</summary>

1. `crictl` knows only pod sandboxes, containers and images. It shows the namespace as a label, but it knows nothing about Deployments or Services — those exist only in the Kubernetes API.
2. A **pod sandbox** is the shared environment of the Pod (network namespace, IP) — held by a tiny `pause` container. **Containers** are your app processes that run inside it.
3. Usually `crictl pods` is equal or higher: it also lists sandboxes that are stopped but not yet garbage-collected (e.g. from deleted or restarted Pods).
4. The **kubelet** noticed the container died and started a **new** container in the same Pod (`ATTEMPT 1`, new container ID). `RESTARTS` went from 0 to 1. The Pod itself (name, IP) stayed the same.
5. (a) `kubectl` (b) `sudo crictl pull nginx` (c) `crictl` — it works even when the API server is down, because it talks directly to containerd on the node.

</details>

## Cleanup

```bash
kubectl delete pod web
```
