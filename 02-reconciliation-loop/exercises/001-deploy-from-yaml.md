# Exercise 001 — Deploy from YAML

**Chapter:** 02 The Reconciliation Loop | **Time:** ~10 min

## Goal

Write desired state in a YAML file, apply it, and map every object Kubernetes created from it.

## Tasks

**1.** Create the file `web.yaml`:

```bash
mkdir -p ~/labs/02 && cd ~/labs/02
cat > web.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels:
    app: web
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
EOF
```

**2.** Apply it and watch the rollout:

```bash
kubectl apply -f web.yaml
kubectl rollout status deployment/web
```

**3.** List everything it created:

```bash
kubectl get deploy,rs,pods -l app=web
```

**4.** Find the owner of each object:

```bash
kubectl describe rs -l app=web | grep "Controlled By"
kubectl describe pods -l app=web | grep "Controlled By"
```

**5.** Draw the hierarchy on paper (or in a text file) with the **real names** from your cluster:

```text
Deployment  ____________
    └── ReplicaSet  ____________
            ├── Pod  ____________
            ├── Pod  ____________
            └── Pod  ____________
```

## Questions

1. In `web.yaml`, which field is the **desired number** of Pods? Which part describes **what each Pod looks like**?
2. How did Kubernetes build the ReplicaSet name? And the Pod names?
3. What does `-l app=web` do in the commands above?
4. Run `kubectl apply -f web.yaml` again without changing anything. What does it print? Why?

<details>
<summary>Solution</summary>

1. `spec.replicas: 3` is the desired number. `spec.template` is the Pod template — every Pod is created from it.
2. ReplicaSet = Deployment name + a hash of the Pod template (e.g. `web-cc544bdcc`). Pod = ReplicaSet name + a random suffix (e.g. `web-cc544bdcc-66vzj`).
3. It filters by **label**: only objects with the label `app=web`. (Labels are covered in the next chapter.)
4. `deployment.apps/web unchanged`. The desired state in the file is already the desired state in the cluster, so there is nothing to change. `apply` is safe to run again and again.

</details>

## Cleanup

Keep the Deployment — the next exercises use it.
