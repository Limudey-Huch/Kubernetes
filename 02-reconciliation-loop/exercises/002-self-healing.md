# Exercise 002 — Self-Healing

**Chapter:** 02 The Reconciliation Loop | **Time:** ~10 min

## Goal

Delete Pods and prove that the ReplicaSet controller always brings the count back to the desired number.

**Needs:** the `web` Deployment from exercise 001.

## Tasks

Keep a second terminal open:

```bash
watch -n1 kubectl get pods -l app=web
```

**1.** Write down the names of the 3 Pods.

**2.** Delete one Pod:

```bash
kubectl delete pod <one-pod-name>
```

**3.** Delete **all** the Pods at once:

```bash
kubectl delete pods -l app=web
```

**4.** Read the story in the events:

```bash
kubectl get events --sort-by=.lastTimestamp | grep -E "replicaset/web|Killing" | tail -10
```

**5.** Check the ReplicaSet:

```bash
kubectl describe rs -l app=web | grep "^Replicas"
kubectl describe rs -l app=web | tail -10
```

## Questions

1. After task 2, how many Pods were there a few seconds later? Did any of them have the old name?
2. After task 3, how long did it take until 3 Pods were `Running` again?
3. Which event reason shows the ReplicaSet creating Pods? Which shows a container being stopped?
4. Did anything you did in this exercise change the **desired** state?
5. Is "deleting a Pod" a good way to restart an app? What is the risk with a Pod that is **not** managed by a Deployment?

<details>
<summary>Solution</summary>

1. 3 again. The new Pod has a **new** name — Pods are replaced, not restarted.
2. A few seconds (the image is already on the node, so no download is needed).
3. `SuccessfulCreate` on the ReplicaSet (`Created pod: web-...`). `Killing` on the Pod (`Stopping container nginx`).
4. No. `replicas: 3` never changed — you only changed the **actual** state, and the controller fixed it.
5. For a Pod managed by a Deployment it works (a new one is created). A bare Pod (`kubectl run`) has no controller above it — delete it and it is gone forever.

</details>

## Cleanup

Keep the Deployment for the next exercise.
