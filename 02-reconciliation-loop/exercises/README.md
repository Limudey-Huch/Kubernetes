# Exercises — 02 The Reconciliation Loop

Short, in-class exercises: change the desired state, break things, and watch Kubernetes reconcile. Do them in order.

**Before you start:** a working cluster, and chapter [02-reconciliation-loop](../02-reconciliation-loop.md) read.

| # | Exercise | Time |
|---|---|---|
| 001 | [Deploy from YAML](001-deploy-from-yaml.md) | 10 min |
| 002 | [Self-healing](002-self-healing.md) | 10 min |
| 003 | [Scaling](003-scaling.md) | 10 min |
| 004 | [Ownership and deletion](004-ownership-and-deletion.md) | 15 min |
| 005 | [Stop the controllers](005-stop-the-controllers.md) | 15 min |
| 006 | [Fix a broken Deployment](006-fix-a-broken-deployment.md) | 15 min |

**Tip:** keep a second terminal open during all exercises:

```bash
watch -n1 kubectl get deploy,rs,pods
```

Each exercise has: a goal, tasks, questions to answer, a hidden solution, and a cleanup step.
Try to answer the questions **before** opening the solution.
