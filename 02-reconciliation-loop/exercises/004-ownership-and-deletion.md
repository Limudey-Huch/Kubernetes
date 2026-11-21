# Exercise 004 — Ownership and Deletion

**Chapter:** 02 The Reconciliation Loop | **Time:** ~15 min

## Goal

Understand how ownership decides what gets deleted: delete each level of the chain, and finally break the chain on purpose.

**Needs:** the `web` Deployment and `~/labs/02/web.yaml` from exercise 001.

## Tasks

Keep a second terminal open:

```bash
watch -n1 kubectl get deploy,rs,pods -l app=web
```

**1.** Look at the owner reference of one Pod:

```bash
kubectl get pods -l app=web -o yaml | grep -A6 ownerReferences | head -8
```

**2.** Delete the ReplicaSet:

```bash
kubectl delete rs -l app=web
```

Watch the second terminal for ~10 seconds.

**3.** Delete the Deployment, but tell Kubernetes **not** to delete its children:

```bash
kubectl delete deployment web --cascade=orphan
kubectl get deploy,rs,pods -l app=web
kubectl describe rs -l app=web | grep "Controlled By" || echo "no owner"
```

**4.** Delete one Pod of the orphaned ReplicaSet:

```bash
kubectl delete pod <one-pod-name>
```

**5.** Bring the Deployment back from the file:

```bash
kubectl apply -f ~/labs/02/web.yaml
kubectl get deploy,rs,pods -l app=web
kubectl describe rs -l app=web | grep "Controlled By"
```

## Questions

1. In task 1, what `kind` is the owner of the Pod? What does `controller: true` mean?
2. After deleting the ReplicaSet (task 2), what happened, and which controller did it?
3. After `--cascade=orphan` (task 3), what still exists? Who is the ReplicaSet's owner now?
4. In task 4, was the deleted Pod replaced? By whom?
5. In task 5, did the Deployment create a new ReplicaSet, or **adopt** the existing one? How can you tell?

<details>
<summary>Solution</summary>

1. `kind: ReplicaSet`. `controller: true` means this owner is the one responsible for managing the Pod.
2. A new ReplicaSet (same name) and new Pods appeared within seconds. The **Deployment controller** saw that its ReplicaSet was missing.
3. The ReplicaSet and its Pods still exist — they are **orphans**, with no owner (`no owner`).
4. Yes — the ReplicaSet controller still manages its own Pods, even without a Deployment above it.
5. It **adopted** the existing ReplicaSet: same name (same Pod template hash), and `Controlled By: Deployment/web` is back. The Pods kept running — the Deployment found objects matching its selector and template and took ownership instead of creating new ones.

</details>

## Cleanup

Keep the Deployment for the next exercise.
