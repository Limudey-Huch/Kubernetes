# 02 — The Reconciliation Loop

How Kubernetes keeps your application running: desired state, actual state, and the controllers that keep checking and fixing the difference.

**Before you start:** a working cluster (`kubectl get nodes` shows `Ready`) and [chapter 01](../01-platform-architecture/01-platform-architecture.md).

This chapter explains. The hands-on part is in the [exercises](exercises/README.md), where you break things and watch Kubernetes repair them.

---

## Goals

By the end of this chapter you can:

- Explain **desired state**, **actual state** and **reconciliation**.
- Describe the chain **Deployment → ReplicaSet → Pod** and why there are three objects.
- Say what a **controller** is and where controllers run.
- Predict what Kubernetes does when you delete each level of the chain.

---

## 1. Kubernetes does not run commands — it keeps a promise

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

This is the **reconciliation loop** (or control loop). It never stops. That is why a crashed Pod comes back without anyone touching it — this is **self-healing**.

Controllers do not replay your commands. Each time around the loop they look at the **current** desired state and close the gap. If you ask for 5 replicas and then for 2 before anything happened, the controller simply makes 2.

---

## 2. Controllers

A **controller** is a small program that runs one reconciliation loop for **one type of object**:

| Controller | Watches | Makes sure that... |
|---|---|---|
| Deployment controller | Deployments | the right ReplicaSet exists |
| ReplicaSet controller | ReplicaSets | the right number of Pods exists |
| Node controller | Nodes | dead nodes are noticed |
| Garbage collector | Owner links | children are deleted when their owner is deleted |

- All the built-in controllers run inside **one** control-plane component: **kube-controller-manager**, a static Pod in `kube-system` (chapter 01).
- It starts them all with `--controllers=*`.
- With `--leader-elect=true`, a cluster with several control-plane nodes runs only **one** active controller-manager at a time (the "leader"). The others wait.
- Controllers never talk to each other. Each one only **watches the API server** and **writes to the API server**.

If kube-controller-manager stops, `kubectl` still works (it talks to the API server), and your changes are still saved — but nothing acts on them until it comes back. [Exercise 005](exercises/005-stop-the-controllers.md) shows this.

---

## 3. The workload hierarchy

One command, `kubectl create deployment hello --image=nginx --replicas=3`, creates **three kinds** of objects:

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

Why three and not one? **Each object has one responsibility.** The ReplicaSet only counts Pods. The Deployment only manages versions — each version of the Pod template gets its own ReplicaSet. Small, focused loops are easier to make reliable.

### Names and owners

- Each child carries its parent's name plus a suffix: `hello` → `hello-558494cd6d` → `hello-558494cd6d-695xs`. The ReplicaSet suffix is a hash of the Pod template.
- Every child records its owner in a field called **`ownerReferences`** (`kubectl describe` shows it as `Controlled By`).
- This link is how Kubernetes knows which controller manages an object, and what to delete when the owner is deleted.

---

## 4. What happens when you change or delete things

| You do | What the loop sees | Who fixes it | Result |
|---|---|---|---|
| Delete a Pod | ReplicaSet: 2 Pods, wants 3 | ReplicaSet controller | A **new** Pod, with a new name. Pods are replaced, never restarted |
| Scale 3 → 5 (or 5 → 2) | ReplicaSet desired number changed | ReplicaSet controller | Pods added (or the newest removed) |
| Delete the ReplicaSet | Deployment: no ReplicaSet for its template | Deployment controller | The ReplicaSet and its Pods come back within seconds |
| Delete the Deployment | The owner is gone | Garbage collector | ReplicaSet and Pods removed. Nothing comes back |

> **Rule:** to really remove an application, delete the object at the **top** (the Deployment). Deleting anything below it only triggers reconciliation.

Notice what each row changes: deleting objects changes the **actual** state, so the controllers repair it. Scaling changes the **desired** state, so the controllers follow it. Deleting the Deployment removes the desired state itself, so there is nothing left to repair.

Try each row in exercises [002](exercises/002-self-healing.md), [003](exercises/003-scaling.md) and [004](exercises/004-ownership-and-deletion.md).

---

## 5. Events: the story of what happened

Controllers and other components report what they do as **events** (`kubectl get events`). After a Pod is deleted, the events read as a chain of responsibility:

```text
ReplicaSet controller → creates the Pod object       (SuccessfulCreate)
Scheduler             → picks a node                  (Scheduled)
kubelet               → pulls image, starts container (Pulled, Created, Started)
```

No component does the whole job. Each one sees a change in the API, does its own step, and writes the result back. The next component picks it up from there.

Events are also the first place to look when something does **not** reconcile — an image that cannot be pulled, or a Pod that no node can take ([exercise 006](exercises/006-fix-a-broken-deployment.md)).

---

## Summary

- Kubernetes stores a **desired state** and continuously makes the **actual state** match it.
- This continuous compare-and-fix is the **reconciliation loop**; it gives us **self-healing**.
- A **controller** runs one loop for one object type. Built-in controllers live in **kube-controller-manager**.
- **Deployment → ReplicaSet → Pod**: each layer owns and manages the next, through `ownerReferences`.
- Deleting a child triggers reconciliation; deleting the **owner** removes everything below it.

### Check yourself

1. You delete a Pod that belongs to a Deployment. Does the same Pod come back? Which controller acts?
2. What is the difference between `kubectl delete pod ...` and `kubectl scale ... --replicas=...`?
3. Why does deleting a ReplicaSet not remove the application?
4. Which control-plane component hosts the Deployment and ReplicaSet controllers?
5. kube-controller-manager is down and you scale a Deployment to 5. Is the request lost?

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

Break things and watch them heal: [exercises/](exercises/README.md)

---

## Further reading

- [Controllers](https://kubernetes.io/docs/concepts/architecture/controller/)
- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [ReplicaSet](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
- [Garbage collection / owners and dependents](https://kubernetes.io/docs/concepts/architecture/garbage-collection/)
