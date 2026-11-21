# Exercise 003 — Scaling

**Chapter:** 02 The Reconciliation Loop | **Time:** ~10 min

## Goal

Change the desired state in two ways — imperatively (`kubectl scale`) and declaratively (edit the YAML) — and see which Pods Kubernetes removes when scaling down.

**Needs:** the `web` Deployment and `~/labs/02/web.yaml` from exercise 001.

## Tasks

Keep a second terminal open:

```bash
watch -n1 kubectl get deploy,rs,pods -l app=web
```

**1.** Scale up with a command:

```bash
kubectl scale deployment web --replicas=6
```

**2.** List the Pods from oldest to newest:

```bash
kubectl get pods -l app=web --sort-by=.metadata.creationTimestamp
```

**3.** Scale down to 2:

```bash
kubectl scale deployment web --replicas=2
kubectl get pods -l app=web --sort-by=.metadata.creationTimestamp
```

**4.** Now the declarative way. Change the file to 4 replicas and apply it:

```bash
cd ~/labs/02
sed -i 's/replicas: 3/replicas: 4/' web.yaml
grep replicas web.yaml
kubectl apply -f web.yaml
```

**5.** Check the Deployment, then scale with a command again and apply the file once more:

```bash
kubectl scale deployment web --replicas=1
kubectl get deploy web
kubectl apply -f web.yaml
kubectl get deploy web
```

## Questions

1. When you scaled up, did the Deployment create a **new** ReplicaSet, or change the existing one?
2. When you scaled down from 6 to 2 — which Pods were removed, the oldest or the newest?
3. After task 5, how many replicas are running? Why?
4. Which way of scaling is better for a team, and why?

<details>
<summary>Solution</summary>

1. It changed the **existing** ReplicaSet (`DESIRED` went from 3 to 6). A new ReplicaSet is created only when the Pod **template** changes (e.g. a new image) — not for replicas.
2. The **newest** ones. The ReplicaSet prefers to keep Pods that have been running longest.
3. **4**. `kubectl scale` set it to 1, but then `apply` sent the file again — and the file says 4. The last desired state written wins.
4. Declarative (the YAML file). The file can be saved in Git, reviewed and reapplied, so the cluster and the file agree. A `kubectl scale` done by hand is lost the next time someone applies the file. (This is the idea behind GitOps / Argo CD, later in the course.)

</details>

## Cleanup

Keep the Deployment for the next exercise.
