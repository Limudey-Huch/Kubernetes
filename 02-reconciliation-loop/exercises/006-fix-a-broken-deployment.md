# Exercise 006 — Fix a Broken Deployment

**Chapter:** 02 The Reconciliation Loop | **Time:** ~15 min

## Goal

Investigate a Deployment that never becomes ready, find the cause using status and events, and fix it by changing the desired state.

## Tasks

**1.** Create a Deployment with a mistake in it:

```bash
kubectl create deployment broken --image=nginx:doesnotexist-123
```

**2.** Investigate. Use only these commands and write down what each tells you:

```bash
kubectl get deploy broken
kubectl get pods -l app=broken
kubectl describe pod -l app=broken | tail -15
kubectl get events --sort-by=.lastTimestamp | grep broken | tail -8
```

**3.** Fix the image:

```bash
kubectl set image deployment/broken nginx=nginx:1.27
kubectl rollout status deployment/broken
```

**4.** Look at the ReplicaSets:

```bash
kubectl get rs -l app=broken
```

**5.** Bonus — break a **healthy** Deployment from YAML, then fix it.

Create a healthy Deployment:

```bash
mkdir -p ~/labs/02 && cd ~/labs/02
cat > app.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app
  template:
    metadata:
      labels:
        app: app
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
EOF
kubectl apply -f app.yaml
kubectl rollout status deployment/app
```

Introduce a typo in the image and apply:

```bash
sed -i 's/nginx:1.27/nginx:1.27-typo/' app.yaml
kubectl apply -f app.yaml
```

Wait 15 seconds, then look:

```bash
kubectl get deploy app
kubectl get pods -l app=app
kubectl get rs -l app=app
```

Now fix `app.yaml` yourself (with `nano app.yaml` or `sed`), apply it again, and check the ReplicaSets once more.

## Questions

1. What `STATUS` did the Pod show? What does it mean?
2. Which event message tells you the **real** cause?
3. Did Kubernetes give up trying? What does `BackOff` mean?
4. After the fix, how many ReplicaSets exist? Why two? What is `DESIRED` for each?
5. During the bonus task, did the old healthy Pods keep running while the new one was failing? Why is that good?
6. After you fixed `app.yaml` in the bonus — did the Deployment create a **third** ReplicaSet, or reuse one? Why?

<details>
<summary>Solution</summary>

1. `ErrImagePull`, then `ImagePullBackOff` — the kubelet cannot download the image.
2. The `Failed` event: `Failed to pull image "nginx:doesnotexist-123": ... not found`.
3. No. Kubernetes keeps retrying (it never stops reconciling), but waits longer between attempts — that growing wait is the **back-off**.
4. Two. Changing the image changed the Pod **template**, so the Deployment created a new ReplicaSet (`DESIRED 1`) and scaled the old one down (`DESIRED 0`). The old one is kept for rollback (a later chapter).
5. Yes. `kubectl get deploy app` showed `READY 2/2` the whole time — both old Pods kept running, and only one new (failing) Pod was added. The Deployment does not remove old Pods until new ones are ready, so a bad change does not take the app down. (Rolling updates are covered in a later chapter.)
6. It **reused** the original ReplicaSet: the fixed template is identical to the first one, so it has the same template hash. The original went back to `DESIRED 2`, and the broken one went to `0`.

</details>

## Cleanup

```bash
kubectl delete deployment broken web app
rm -f ~/labs/02/app.yaml
```
