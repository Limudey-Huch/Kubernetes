# Exercise 005 — Stop the Controllers

**Chapter:** 02 The Reconciliation Loop | **Time:** ~15 min

## Goal

Prove that reconciliation is done by **kube-controller-manager**: stop it, see that nothing heals anymore, then start it again and watch it catch up.

**Needs:** the `web` Deployment from the previous exercises.

> ⚠️ In this exercise you temporarily stop a control-plane component. Follow the steps exactly and **always do the "restore" step**. If something goes wrong, revert to your `cluster-ready` snapshot.

## Tasks

Keep a second terminal open:

```bash
watch -n1 kubectl get deploy,rs,pods -l app=web
```

**1.** Make sure the Deployment has 3 replicas:

```bash
kubectl scale deployment web --replicas=3
kubectl get pods -n kube-system | grep controller-manager
```

**2.** Stop the controller-manager by moving its static Pod file out of the manifests folder:

```bash
sudo mv /etc/kubernetes/manifests/kube-controller-manager.yaml /tmp/
```

Wait until it is gone (~20 seconds):

```bash
kubectl get pods -n kube-system | grep controller-manager || echo "controller-manager is stopped"
```

**3.** Delete a Pod:

```bash
kubectl delete pod <one-web-pod-name>
```

**4.** Change the desired state:

```bash
kubectl scale deployment web --replicas=5
kubectl get deploy web
```

Wait 20 seconds and look at the second terminal.

**5.** Restore the controller-manager:

```bash
sudo mv /tmp/kube-controller-manager.yaml /etc/kubernetes/manifests/
```

Watch the second terminal for ~30 seconds.

**6.** Confirm it is back:

```bash
kubectl get pods -n kube-system | grep controller-manager
ls /etc/kubernetes/manifests/
```

## Questions

1. While the controller-manager was stopped, did `kubectl` still work? Why?
2. After you deleted a Pod (task 3), was it replaced?
3. After `scale --replicas=5` (task 4): what did `kubectl get deploy web` show in the `READY` column? Did the ReplicaSet's `DESIRED` change?
4. Where was your "5 replicas" request stored while no controller was running?
5. What happened as soon as the controller-manager came back?

<details>
<summary>Solution</summary>

1. Yes. `kubectl` talks only to the **API server**, which was still running. Reads and writes to the API worked normally.
2. **No.** No controller was watching, so nobody noticed the missing Pod.
3. `READY` showed something like `2/5`: the Deployment's desired number changed to 5, but the ReplicaSet stayed at its old `DESIRED` — the Deployment controller that would update it was stopped.
4. In **etcd**, through the API server. The desired state was saved — only the "act" part of the loop was missing.
5. It read the desired state, compared it with reality, and fixed everything at once: the ReplicaSet went to 5 and new Pods were created until `5/5`. This is reconciliation: controllers don't replay commands — they look at the **current** desired state and close the gap.

</details>

## Cleanup

Make sure the controller-manager file is back:

```bash
ls /etc/kubernetes/manifests/kube-controller-manager.yaml
kubectl get pods -n kube-system | grep controller-manager
```

Keep the `web` Deployment for the next exercise.
