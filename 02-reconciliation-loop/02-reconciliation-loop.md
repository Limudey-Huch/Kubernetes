# 02 — The Reconciliation Loop

How Kubernetes keeps your application running: desired state, actual state, and the controllers that keep checking and fixing the difference.

**Before you start:** a working cluster from [01-platform-architecture](../01-platform-architecture/01-platform-architecture.md) (`kubectl get nodes` shows `Ready`).

---

## Goals

By the end of this chapter you can:

- Explain **desired state**, **actual state** and **reconciliation**.
- Describe the chain **Deployment → ReplicaSet → Pod** and why there are three objects.
- Say what a **controller** is and where controllers run.
- Show self-healing in practice: delete things and watch Kubernetes bring them back.

---

## Part 1 — Theory

### Kubernetes does not run commands — it keeps a promise

With Docker you give **commands**: "run this container". It runs once. If it dies, it stays dead (unless a restart policy catches it on that same host).

With Kubernetes you declare **what should exist**: "there should always be 3 copies of nginx". Kubernetes stores that in etcd and **keeps checking** that it is true — forever.

| | Meaning | Where it lives |
|---|---|---|
| **Desired state** | What you asked for (`replicas: 3`, image `nginx`) | In the API / etcd |
| **Actual state** | What is really running right now | On the nodes |
| **Reconciliation** | Making actual state match desired state | Done by controllers |

### The loop

```text
            Desired State  (stored in the API)
                  │
                  ▼
     ┌──► Controller observes actual state
     │            │
     │            ▼
     │     Desired == Actual ?
     │       │            │
     │      yes           no
     │       │            │
     │       │            ▼
     │       │     Act: create / delete / update
     │       │            │
     └───────┴────────────┘
              (forever)
```

This is called the **reconciliation loop** (or control loop). It never stops. That is why a crashed Pod comes back without anyone touching it — this is **self-healing**.

### Controllers

A **controller** is a small program that runs one reconciliation loop for **one type of object**:

| Controller | Watches | Makes sure that... |
|---|---|---|
| Deployment controller | Deployments | the right ReplicaSet exists |
| ReplicaSet controller | ReplicaSets | the right number of Pods exists |
| Node controller | Nodes | dead nodes are noticed |
| Garbage collector | Owner links | children are deleted when their owner is deleted |

All the built-in controllers run inside **one** control-plane component: **kube-controller-manager** (we saw it as a static Pod in chapter 01).

Controllers never talk to each other directly. Each one only **watches the API server** and **writes to the API server**.

---

## Part 2 — The workload hierarchy

### Deploy an application

```bash
kubectl create deployment hello --image=nginx --replicas=3
kubectl get deploy,rs,pods
```

```text
NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/hello   3/3     3            3           4s

NAME                               DESIRED   CURRENT   READY   AGE
replicaset.apps/hello-558494cd6d   3         3         3       4s

NAME                         READY   STATUS    RESTARTS   AGE
pod/hello-558494cd6d-695xs   1/1     Running   0          4s
pod/hello-558494cd6d-dhdvr   1/1     Running   0          4s
pod/hello-558494cd6d-rdbdt   1/1     Running   0          4s
```

One command created **three kinds** of objects.

```text
Deployment  hello                     "I want 3 nginx Pods, this version"
    │ owns
    ▼
ReplicaSet  hello-558494cd6d          "I keep exactly 3 Pods alive"
    │ owns
    ├──► Pod  hello-558494cd6d-695xs  "I am a running container"
    ├──► Pod  hello-558494cd6d-dhdvr
    └──► Pod  hello-558494cd6d-rdbdt
```

| Object | Job |
|---|---|
| **Deployment** | Describes the application (image, replicas). Handles **version changes** (rolling updates — later chapter). |
| **ReplicaSet** | Keeps the **number** of Pods correct. Nothing more. |
| **Pod** | The actual running container(s). Disposable. |

Why three and not one? **Each object has one responsibility.** The ReplicaSet only counts Pods. The Deployment only manages versions (each version gets its own ReplicaSet). Small, focused loops are easier to make reliable.

> Notice the names: `hello` → `hello-558494cd6d` → `hello-558494cd6d-695xs`. Each child carries its parent's name plus a random suffix.

### Who owns whom?

```bash
kubectl describe rs -l app=hello | grep "Controlled By"
kubectl describe pod -l app=hello | grep "Controlled By"
```

```text
Controlled By:  Deployment/hello
Controlled By:  ReplicaSet/hello-558494cd6d
```

Every child records its owner (in a field called `ownerReferences`). This link is how Kubernetes knows what to clean up later.

### Where do the controllers run?

```bash
kubectl get pods -n kube-system | grep controller-manager
```

```text
kube-controller-manager-k8s-lab   1/1     Running   0          20m
```

```bash
sudo ps -ww -C kube-controller-manager -o args= | tr ' ' '\n' | grep -E '^--controllers|^--leader'
```

```text
--controllers=*,bootstrapsigner,tokencleaner
--leader-elect=true
```

- `--controllers=*` — run all the built-in controllers.
- `--leader-elect=true` — in a cluster with several control-plane nodes, only one controller-manager is active at a time (the "leader").

---

## Part 3 — Watch reconciliation happen

Open **two terminals** to the VM.

**Terminal 1** — keep this running for all the experiments:

```bash
watch -n1 kubectl get deploy,rs,pods
```

Run each experiment in **Terminal 2** and watch Terminal 1.

### Experiment 1 — Delete a Pod

```bash
kubectl delete pod <one-of-the-hello-pods>
```

What you see in Terminal 1:

```text
pod/hello-558494cd6d-58j9h   0/1     ContainerCreating   0     1s    ← new Pod
pod/hello-558494cd6d-5qnrd   1/1     Terminating         0     15s   ← the one you deleted
pod/hello-558494cd6d-vb9hg   1/1     Running             0     15s
pod/hello-558494cd6d-ztlp9   1/1     Running             0     15s
```

What happened:

```text
desired: 3 Pods      actual: 2 Pods
          └── ReplicaSet controller: "1 missing" ──► creates a new Pod
```

The new Pod has a **new name**. Kubernetes did not "restart" the old Pod — it replaced it. Pods are disposable.

### Experiment 2 — Change the desired state (scale)

```bash
kubectl scale deployment hello --replicas=5
```

```text
replicaset.apps/hello-558494cd6d   5         5         5       7s
```

Two new Pods appear. Now scale down:

```bash
kubectl scale deployment hello --replicas=2
```

Three Pods go to `Terminating`. We changed only the **desired** number — the controllers did the rest.

### Experiment 3 — Delete the ReplicaSet

```bash
kubectl delete rs -l app=hello
```

```text
NAME                               DESIRED   CURRENT   READY   AGE
replicaset.apps/hello-558494cd6d   2         2         2       4s
```

The ReplicaSet was deleted (and its Pods with it) — and **4 seconds later it is back**, with new Pods. Why? The **Deployment** still exists and still says "I want a ReplicaSet with 2 Pods". The Deployment controller reconciled.

### Experiment 4 — Delete the Deployment

```bash
kubectl delete deployment hello
```

```text
No resources found in default namespace.
```

This time nothing comes back. The Deployment was the **top of the chain** — the desired state itself. With the owner gone, the **garbage collector** removed the ReplicaSet and the Pods.

### Summary of the experiments

| You deleted | Who fixed it | Result |
|---|---|---|
| A Pod | ReplicaSet controller | New Pod created |
| *(changed replicas)* | ReplicaSet controller | Pods added / removed |
| The ReplicaSet | Deployment controller | New ReplicaSet + Pods created |
| The Deployment | Garbage collector | Everything below it removed |

> **Rule:** to really remove an application, delete the object at the **top** (the Deployment). Deleting things below it only triggers reconciliation.

---

## Part 4 — Events: the story of what happened

Controllers report what they do as **events**:

```bash
kubectl create deployment hello --image=nginx --replicas=3
kubectl delete pod $(kubectl get pods -l app=hello -o name | head -1 | cut -d/ -f2)
kubectl get events --sort-by=.lastTimestamp | tail -10
```

Look for the lines about the **new** Pod (events from the other Pods are mixed in):

```text
Normal  Killing           pod/hello-558494cd6d-5qnrd     Stopping container nginx
Normal  SuccessfulCreate  replicaset/hello-558494cd6d    Created pod: hello-558494cd6d-58j9h
Normal  Scheduled         pod/hello-558494cd6d-58j9h     Successfully assigned default/hello-558494cd6d-58j9h to k8s-lab
Normal  Pulled            pod/hello-558494cd6d-58j9h     Successfully pulled image "nginx" ...
Normal  Created           pod/hello-558494cd6d-58j9h     Container created
Normal  Started           pod/hello-558494cd6d-58j9h     Container started
```

Read it as a chain of responsibility:

```text
ReplicaSet controller → creates the Pod object       (SuccessfulCreate)
Scheduler             → picks a node                  (Scheduled)
kubelet               → pulls image, starts container (Pulled, Created, Started)
```

Clean up:

```bash
kubectl delete deployment hello
```

---

## Summary

- Kubernetes stores a **desired state** and continuously makes the **actual state** match it.
- This continuous compare-and-fix is the **reconciliation loop**; it gives us **self-healing**.
- A **controller** runs one loop for one object type. Built-in controllers live in **kube-controller-manager**.
- **Deployment → ReplicaSet → Pod**: each layer owns and manages the next.
- Deleting a child triggers reconciliation; deleting the **owner** removes everything below it.

### Check yourself

1. You delete a Pod that belongs to a Deployment. Does the same Pod come back? Which controller acts?
2. What is the difference between `kubectl delete pod ...` and `kubectl scale ... --replicas=...`?
3. Why does deleting a ReplicaSet not remove the application?
4. Which control-plane component hosts the Deployment and ReplicaSet controllers?

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Deleted Pod is not replaced, `scale` does nothing | kube-controller-manager is not running or restarting | `kubectl get pods -n kube-system`, `kubectl logs -n kube-system kube-controller-manager-<node>` |
| controller-manager / scheduler restarted for no reason | The VM was frozen for a moment (e.g. a VMware snapshot with memory) and they lost their leader lease | Normal after a snapshot; they recover by themselves within seconds |
| New Pod stuck in `ContainerCreating` | Image is still downloading | `kubectl describe pod <name>` → Events |
| Pods stuck in `Pending` | No node can take them (taint, resources) | `kubectl describe pod <name>` → Events |

---

## Exercises

In-class exercises for this chapter: [exercises/](exercises/README.md)

---

## Further reading

- [Controllers](https://kubernetes.io/docs/concepts/architecture/controller/)
- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
- [Garbage collection / owners and dependents](https://kubernetes.io/docs/concepts/architecture/garbage-collection/)
