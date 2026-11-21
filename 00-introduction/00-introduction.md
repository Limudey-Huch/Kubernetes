# 00 — Introduction to Kubernetes

What problem Kubernetes solves, what a cluster looks like, and when it is (and isn't) the right tool.

---

## 1. Where we are coming from: Docker on one server

With Docker we already know how to package an application into an **image** and run it as a **container**:

```text
docker CLI
    │
    ▼
Docker Engine
    │
    ▼
Containers   (on ONE machine)
```

This works well on a laptop or a single server. In production, things get harder very quickly.

### Questions Docker alone does not answer

| Problem | What happens with plain Docker |
|---|---|
| A container crashes at 3 AM | `--restart` helps on that machine, but nobody moves it if the whole server dies |
| The server dies | Every container on it is gone until a human reacts |
| Traffic grows ×10 | You manually start more containers and update the load balancer |
| You have 20 servers | Which server has free CPU/RAM for the next container? You decide, by hand |
| Container IPs keep changing | Other services must somehow find the new IP |
| Deploying a new version | Stop old, start new → downtime, and rollback is manual |
| Secrets and config | Spread across `docker run -e ...` commands and scripts |
| "What is supposed to be running?" | The only truth is what is running right now. There is no record of the intended state |

Running containers on **many machines**, reliably, without a human doing it by hand, is called **container orchestration**. Kubernetes is the industry-standard container orchestrator.

---

## 2. What Kubernetes is

> **Kubernetes (K8s)** is an open-source platform that runs and manages containerized workloads across a group of machines (a **cluster**), and keeps them in the state you declared.

The key idea is **declarative desired state**:

```text
Imperative (Docker style)         Declarative (Kubernetes style)
───────────────────────           ──────────────────────────────
"Run 3 containers now."           "There should ALWAYS be 3 replicas
                                   of this app, version 1.4."
You run it. If one dies,
you notice and fix it.            Kubernetes keeps checking and fixing
                                  until reality matches the declaration.
```

You describe **what** you want (usually in YAML). Kubernetes continuously works on **how** to make it true. This never-ending "compare and fix" cycle is called the **reconciliation loop**:

```text
        ┌───────────────────────────────────┐
        │                                   │
        ▼                                   │
  Observe actual state                      │
        │                                   │
        ▼                                   │
  Compare to desired state                  │
        │                                   │
        ▼                                   │
  Act to remove the difference ─────────────┘
  (start / stop / move / replace)
```

### Mental model shift

```text
Docker model                   Kubernetes model
────────────                   ────────────────
docker CLI                     kubectl
    │                              │
    ▼                              ▼
Docker Engine                  Kubernetes API (kube-apiserver)
    │                              │
    ▼                              ▼
Containers                     API Resources (Deployments, Pods, Services ...)
                                   │
                                   ▼
                               Containers (run by containerd on the nodes)
```

With Kubernetes you no longer talk to containers. You talk to **one API** and create **resources**; the platform turns them into running containers.

---

## 3. What Kubernetes gives you

| Capability | Meaning |
|---|---|
| **Self-healing** | Crashed containers restart; Pods on a dead node are recreated elsewhere |
| **Scheduling** | Picks a node with enough CPU/RAM for every workload |
| **Scaling** | `replicas: 3` → `replicas: 10`, manually or automatically by load |
| **Service discovery & load balancing** | A stable name + virtual IP in front of changing Pods |
| **Rolling updates & rollback** | Replace versions gradually, with no downtime; undo with one command |
| **Configuration & secrets** | ConfigMaps and Secrets, separate from the image |
| **Storage orchestration** | Attach persistent volumes to workloads that need data |
| **Extensibility** | Add new resource types and controllers (e.g., Argo CD, Prometheus Operator) |

---

## 4. Cluster architecture

A Kubernetes **cluster** is a set of machines called **nodes**. Nodes have two roles:

- **Control plane** — the "brain". Stores state, makes decisions, exposes the API.
- **Worker nodes** — the "muscle". Actually run the application containers.

### Production topology (typical)

```text
                              Users / Admins
                                    │ kubectl (HTTPS :6443)
                                    ▼
┌───────────────────────────── CONTROL PLANE ─────────────────────────────┐
│                                                                         │
│   ┌──────────────────┐     ┌────────┐                                   │
│   │  kube-apiserver  │◄───►│  etcd  │   (cluster database)              │
│   └────────▲─────────┘     └────────┘                                   │
│            │                                                            │
│   ┌────────┴───────────┐   ┌────────────────┐                           │
│   │ controller-manager │   │   scheduler    │                           │
│   └────────────────────┘   └────────────────┘                           │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │  (all communication goes
                                     │   through the API server)
          ┌──────────────────────────┼──────────────────────────┐
          ▼                          ▼                          ▼
┌─────── worker-1 ───────┐ ┌─────── worker-2 ───────┐ ┌─────── worker-3 ───────┐
│ kubelet                │ │ kubelet                │ │ kubelet                │
│ kube-proxy             │ │ kube-proxy             │ │ kube-proxy             │
│ containerd             │ │ containerd             │ │ containerd             │
│ CNI plugin             │ │ CNI plugin             │ │ CNI plugin             │
│ ┌─────┐ ┌─────┐        │ │ ┌─────┐ ┌─────┐        │ │ ┌─────┐                │
│ │ Pod │ │ Pod │        │ │ │ Pod │ │ Pod │        │ │ │ Pod │                │
│ └─────┘ └─────┘        │ │ └─────┘ └─────┘        │ │ └─────┘                │
└────────────────────────┘ └────────────────────────┘ └────────────────────────┘
```

Production clusters usually run **3 control-plane nodes** (for high availability of etcd and the API) and any number of workers.

### Control-plane components

| Component | Role |
|---|---|
| **kube-apiserver** | The front door. Every request (kubectl, controllers, kubelets) goes through it. Validates, authenticates, stores into etcd. Listens on **6443** (HTTPS). |
| **etcd** | Distributed key-value store. Holds the **entire cluster state** — the desired state of every object. Only the API server talks to it. |
| **kube-scheduler** | Watches for new Pods without a node and picks the best node for each one (based on free resources, rules, affinity). |
| **kube-controller-manager** | Runs the built-in **controllers** (Deployment, ReplicaSet, Node, Job ...). Each controller runs a reconciliation loop for its resource type. |

### Node components (run on every node)

| Component | Role |
|---|---|
| **kubelet** | The node agent. Gets the Pods assigned to its node from the API server and makes sure their containers are running and healthy. |
| **Container runtime (containerd)** | Actually pulls images and runs containers. kubelet talks to it through the **CRI** (Container Runtime Interface). |
| **kube-proxy** | Implements **Services** on the node (iptables/IPVS rules) so traffic to a Service IP reaches a healthy Pod. |
| **CNI plugin** (Flannel, Calico, Cilium ...) | Gives every Pod an IP address and connects Pods across nodes. |

### Cluster add-ons

| Add-on | Role |
|---|---|
| **CoreDNS** | Cluster DNS. Lets Pods find Services by name (`my-svc.my-namespace.svc.cluster.local`). |
| **Ingress controller** (optional) | HTTP/HTTPS routing from outside into Services. |
| **Metrics server** (optional) | CPU/RAM metrics for `kubectl top` and autoscaling. |

---

## 5. Our lab topology

In this course we use **kubeadm** to build a **single-node cluster** inside one Ubuntu VM. The same node is both control plane and worker. All the real components are present — just on one machine.

```text
┌──────────────────────── Host machine (laptop / PC) ─────────────────────────┐
│                                                                             │
│   Browser, SSH client                                                       │
│        │                                                                    │
│        ▼                                                                    │
│ ┌──────────────────── Ubuntu VM  (static IP, e.g. 192.168.x.10) ──────────┐ │
│ │                                                                         │ │
│ │   kubectl ──► kube-apiserver :6443 ◄──► etcd                            │ │
│ │                    ▲                                                    │ │
│ │          scheduler │ controller-manager        (static Pods in          │ │
│ │                    │                            /etc/kubernetes/        │ │
│ │                    ▼                            manifests)              │ │
│ │                 kubelet ──CRI──► containerd                             │ │
│ │                                     │                                   │ │
│ │       ┌─────────────────────────────┼──────────────────────────┐        │ │
│ │       ▼                             ▼                          ▼        │ │
│ │   kube-system Pods            Our app Pods             Later in course: │ │
│ │   (CoreDNS, kube-proxy,       (labs)                   Argo CD,         │ │
│ │    CNI)                                                Prometheus,      │ │
│ │                                                        Grafana          │ │
│ │   Pod network: 10.244.0.0/16      Service network: 10.96.0.0/12         │ │
│ └─────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

Why single-node:

- One VM, low hardware cost — see [../vm-requirements.md](../vm-requirements.md).
- Every concept (API, controllers, scheduling, networking, storage) behaves the same as on a multi-node cluster.
- kubeadm is the **official** upstream installer, so what we see is "real" Kubernetes, not a simplified distribution.

What a single node cannot show: true node failure / Pod rescheduling to another node, and multi-node HA. We discuss these in theory.

### Other ways to run Kubernetes (for context)

| Option | Use case |
|---|---|
| **kubeadm** (our choice) | Real upstream cluster on your own machines/VMs |
| minikube, kind, k3d | Quick local dev clusters (VM or containers) |
| k3s, MicroK8s | Lightweight distributions, edge, small servers |
| EKS, AKS, GKE | Managed Kubernetes in the cloud — the provider runs the control plane |
| OpenShift, Rancher | Enterprise platforms built on top of Kubernetes |

---

## 6. Basic building blocks (preview)

These are covered in detail in the coming chapters. A first look:

```text
Namespace  (logical grouping, e.g. "dev", "prod")
   │
   ├── Deployment  "web"          ← desired state: image + replicas
   │      │ manages
   │      ▼
   │   ReplicaSet                  ← keeps N identical Pods alive
   │      │ creates
   │      ▼
   │   Pod  Pod  Pod               ← smallest unit; one or more containers
   │    ▲    ▲    ▲                  sharing IP + volumes
   │    └────┼────┘
   │         │ selects by label
   └── Service "web"               ← stable name + IP, load-balances to Pods
```

| Object | One-line meaning |
|---|---|
| **Pod** | Smallest deployable unit. Wraps one (or a few tightly-coupled) containers with a shared IP. Pods are disposable. |
| **ReplicaSet** | Ensures a given number of identical Pods are running. |
| **Deployment** | Manages ReplicaSets; adds rolling updates and rollback. What we normally use for stateless apps. |
| **Service** | Stable virtual IP + DNS name in front of a changing set of Pods. |
| **Namespace** | Logical partition of the cluster for organization and access control. |
| **Labels / Selectors** | Key-value tags; the "glue" that connects Services and controllers to Pods. |
| **ConfigMap / Secret** | Configuration and sensitive data injected into Pods. |

A minimal example of desired state:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
```

```bash
kubectl apply -f web.yaml    # declare desired state
kubectl get pods             # see Kubernetes make it true
```

---

## 7. How a request flows through the cluster

What happens after `kubectl apply -f web.yaml`:

```text
1. kubectl ──HTTPS──► kube-apiserver
                         │ authenticate, authorize, validate
                         ▼
2.                     etcd  ← Deployment "web" (replicas: 3) stored

3. Deployment controller (controller-manager) sees new Deployment
                         └─► creates a ReplicaSet

4. ReplicaSet controller sees 0 of 3 Pods
                         └─► creates 3 Pod objects (no node yet)

5. Scheduler sees 3 unscheduled Pods
                         └─► assigns each Pod to a node

6. kubelet on that node sees Pods assigned to it
                         └─► asks containerd (CRI) to pull image + start containers
                         └─► CNI gives each Pod an IP

7. kubelet reports status back ──► API server ──► etcd
                         "3/3 Running"
```

Notice: **no component calls another directly**. Everything is coordinated by writing to and watching the API server. That is what makes Kubernetes resilient and extensible.

---

## 8. When to use Kubernetes — and when not to

### Good fit

- Microservices: many services that are deployed, scaled and updated independently.
- Applications that need **high availability** and self-healing.
- Variable traffic that benefits from **scaling** up and down.
- Teams that want **frequent, zero-downtime releases** with rollback.
- Running the same workloads across environments (on-prem, cloud, multi-cloud) with one API.
- Platform teams building internal tooling on top of a common API (GitOps, monitoring, CI runners).

### Probably not worth it

- A single small app or a static website — a VM, Docker Compose or a PaaS is simpler.
- A small team with no one to own the cluster — Kubernetes has real operational cost (upgrades, security, networking, monitoring).
- Workloads that don't run in containers and can't easily be containerized.
- When you only need "run a container somewhere" — serverless containers (Cloud Run, ECS Fargate, Azure Container Apps) may be enough.

### Rule of thumb

> Kubernetes trades **simplicity** for **automation at scale**. If you don't need the automation, you are paying the complexity cost for nothing.

| Need | Simpler option | When to move to K8s |
|---|---|---|
| 1–3 containers on one host | Docker Compose | Need multiple hosts, HA, rolling updates |
| Simple web app | PaaS (Heroku-like, App Service) | Many services, custom networking, platform tooling |
| Event-driven functions | Serverless | Long-running services, full control over runtime |

---

## 9. Key terms

| Term | Meaning |
|---|---|
| Cluster | A set of nodes managed by one control plane |
| Node | A machine (VM or physical) in the cluster |
| Control plane | Components that store state and make decisions |
| Desired state | What you declared (stored in etcd) |
| Actual state | What is really running right now |
| Reconciliation | Continuously moving actual state toward desired state |
| Controller | A loop that reconciles one type of resource |
| Manifest | A YAML/JSON file describing a resource |
| kubectl | The command-line client for the Kubernetes API |
| CRI / CNI | Plug-in interfaces for container runtime / networking |

---

## 10. Further reading

- [Kubernetes Overview — kubernetes.io](https://kubernetes.io/docs/concepts/overview/)
- [Cluster Architecture — kubernetes.io](https://kubernetes.io/docs/concepts/architecture/)
- [Kubernetes Components — kubernetes.io](https://kubernetes.io/docs/concepts/overview/components/)
- [Installing kubeadm — kubernetes.io](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)
