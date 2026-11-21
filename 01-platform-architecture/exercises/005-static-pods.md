# Exercise 005 — Static Pods

**Chapter:** 01 Platform Architecture | **Time:** ~15 min

## Goal

Understand how the kubelet starts the control plane: by creating your own static Pod.

## Tasks

**1.** Look at the kubelet service and where it reads static Pods from:

```bash
systemctl status kubelet --no-pager | head -5
sudo grep staticPodPath /var/lib/kubelet/config.yaml
```

**2.** Create a static Pod by dropping a file into that folder:

```bash
cat <<EOF | sudo tee /etc/kubernetes/manifests/static-web.yaml
apiVersion: v1
kind: Pod
metadata:
  name: static-web
spec:
  containers:
    - name: nginx
      image: nginx
EOF
```

Wait ~10 seconds:

```bash
kubectl get pods
```

**3.** Try to delete it with kubectl:

```bash
kubectl delete pod static-web-k8s-lab
kubectl get pods
```

(Use the exact Pod name you saw — it ends with your node name.)

**4.** Now remove the file:

```bash
sudo rm /etc/kubernetes/manifests/static-web.yaml
```

Wait ~10 seconds:

```bash
kubectl get pods
```

## Questions

1. What is the full name of the Pod? Why does it end with the node name?
2. You did not run `kubectl apply`. Who created the Pod?
3. What happened when you ran `kubectl delete pod`? Why?
4. What finally removed the Pod?
5. Why does kubeadm run etcd and kube-apiserver as static Pods and not as a Deployment?

<details>
<summary>Solution</summary>

1. `static-web-k8s-lab`. The kubelet adds the node name, because a static Pod belongs to one specific node.
2. The **kubelet**. It watches `/etc/kubernetes/manifests` (`staticPodPath`) and runs any Pod file it finds there — no API server involved.
3. The Pod came back almost immediately. What you see in `kubectl` is only a **mirror Pod** — a read-only copy the kubelet publishes to the API. The real source is the file on disk, so deleting the mirror does nothing.
4. Deleting the **file**. The kubelet noticed and stopped the Pod.
5. A Deployment needs the API server, etcd and the controller-manager to already be running. The control plane can't depend on itself to start — so the kubelet starts it directly from files.

</details>

## Cleanup

Make sure the file is gone:

```bash
ls /etc/kubernetes/manifests/
```

Only `etcd.yaml`, `kube-apiserver.yaml`, `kube-controller-manager.yaml` and `kube-scheduler.yaml` should remain.

> ⚠️ Never edit or delete those four files during exercises — they are your control plane.
