# Exercise 004 — Namespaces and API Resources

**Chapter:** 01 Platform Architecture | **Time:** ~10 min

## Goal

Learn to discover what the API offers, and work with namespaces.

## Tasks

**1.** List all resource types the cluster knows:

```bash
kubectl api-resources
```

**2.** Count namespaced and cluster-wide types:

```bash
kubectl api-resources --namespaced=true -o name | wc -l
kubectl api-resources --namespaced=false -o name | wc -l
kubectl api-resources --namespaced=false
```

**3.** Ask the API to explain a resource:

```bash
kubectl explain pod
kubectl explain pod.spec.containers.image
```

**4.** Create your own namespace and run a Pod in it:

```bash
kubectl create namespace lab
kubectl run web --image=nginx -n lab
kubectl get pods
kubectl get pods -n lab
kubectl get pods -A | grep web
```

**5.** Make `lab` your default namespace, then switch back:

```bash
kubectl config set-context --current --namespace=lab
kubectl get pods
kubectl config set-context --current --namespace=default
```

## Questions

1. What is the short name of `pods`? `services`? `namespaces`? `deployments`? (Look at the `SHORTNAMES` column.)
2. Name three cluster-wide (non-namespaced) resources.
3. In task 4, why does `kubectl get pods` (without `-n`) not show `web`?
4. Can two Pods named `web` exist at the same time? Under what condition?
5. Is a Node namespaced? Why does that make sense?

<details>
<summary>Solution</summary>

1. `po`, `svc`, `ns`, `deploy`. Example: `kubectl get po`, `kubectl get svc -A`.
2. For example: `nodes`, `namespaces`, `persistentvolumes`, `clusterroles`, `storageclasses`.
3. Without `-n`, kubectl uses the current namespace (`default`). `web` lives in `lab`.
4. Yes — if they are in **different namespaces**. Names must be unique only inside a namespace.
5. No. A node is a machine that serves the whole cluster; Pods from every namespace run on it. It cannot belong to just one namespace.

</details>

## Cleanup

```bash
kubectl config set-context --current --namespace=default
kubectl delete namespace lab
```

Deleting the namespace deletes everything inside it.
