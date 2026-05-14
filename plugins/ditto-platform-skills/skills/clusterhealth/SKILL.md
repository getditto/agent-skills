---
name: clusterhealth
description: Check Kubernetes cluster health or list available clusters. Use when user asks to check cluster health, diagnose a cluster, list clusters, or get infrastructure status for a Ditto-managed cluster. Requires a mgmt or ops kubectl context.
allowed-tools: Bash, Task, TaskCreate, TaskOutput, TaskGet
---

# Cluster Health Check

Checks the health of a Ditto Kubernetes cluster. The resource scan runs as a background task so the conversation stays responsive during the 1-2 minute scan.

## Step 1: Verify kubectl Context

```bash
kubectl config current-context
```

If the context contains `mgmt-` or `ops.k8s.ditto.live`, proceed to Step 2 using that context.

If not, list all available contexts and filter to mgmt/ops candidates:

```bash
kubectl config get-contexts --no-headers -o name | grep -E "(mgmt-|ops\.k8s\.ditto\.live)"
```

If matching contexts are found, display them as a numbered list and ask:
> "You're not in a mgmt or ops context. Which context would you like to use?"

Wait for the user's selection, then set `CONTEXT` to the chosen value and proceed to Step 2.

If no matching contexts are found at all, respond:
> "No mgmt or ops kubectl contexts found. Connect via Teleport and try again."

Stop here.

## Step 2: Identify Target Cluster

List available clusters using the selected context:

```bash
kubectl get namespaces --context <CONTEXT> | grep "^cluster-" | sed 's/cluster-//'
```

If the user already specified a cluster name, skip the listing and proceed directly to Step 3.

Otherwise display the results as a numbered list (with `cluster-` prefix stripped) and ask the user which cluster to check. Wait for their selection before proceeding.

## Step 3: Spawn Background Health Check

Tell the user:
> "Running health check for `<cluster-name>` in the background — I'll report back when it's done."

Use the **Task tool** with `run_in_background: true`, passing the prompt below (substituting the real cluster name for `<CLUSTER_NAME>` and the selected context for `<CONTEXT>`):

---

```
Run a full health check for the Ditto cluster <CLUSTER_NAME> using kubectl context <CONTEXT>.
Use --context <CONTEXT> on every kubectl command below.

### Pre-check
Verify the namespace exists:
  kubectl get namespace cluster-<CLUSTER_NAME> --context <CONTEXT>
If it doesn't exist, return: "Health report is not available for that cluster." and stop.

### Cluster Status
Check the official cluster status from the ArgoCD secret:
  kubectl get secret cluster-<CLUSTER_NAME> -n argo --context <CONTEXT> -o yaml | grep 'ditto.live/cluster_status'

### Full Resource Scan
Run the full resource scan (takes 1-2 minutes):
  kubectl get -A $(kubectl api-resources --no-headers -o name --context <CONTEXT> | grep -E -v 'events|nodes|bindings|subjectaccessreviews' | paste -s -d, -) --no-headers --context <CONTEXT> 2>/dev/null | grep '<CLUSTER_NAME>'

### Provisioned Status (only if cluster_status is "Provisioned")
If the cluster is stuck in Provisioned state, check valet-cluster-operator logs for blockers:
  kubectl logs -n valet-system -l app=valet-cluster-operator --tail=200 --context <CONTEXT> 2>/dev/null | grep -iE '(error|fail|dns|cloudarmor|nat router|kubeconfig)'

### Analysis
Produce a health report with these sections:

**Official Status** — cluster_status label value and what it means

**Infrastructure** — control plane machines (count, zones, version), worker nodes (count, deployment groups), addons (CloudController, EBS CSI, Cert-Manager, Cilium, etc.)

**Application Health** — list all pods with their state; flag anything not in Running or Completed state

**ArgoCD** — total app count, how many Synced+Healthy, and a list of any Degraded or OutOfSync apps

**Security** — certificates (valid/expired), external secrets (synced/failed), secret stores status

**Networking** — services, endpoints, DNS records, ingress/envoy status

**Monitoring** — Datadog, Prometheus, Vector application health

**Issues Requiring Attention** — table with columns: Severity (CRITICAL/HIGH/MEDIUM/LOW) | Issue | Detail

Rules:
- Ignore method errors
- Only include deprecation warnings if deprecated resources are actually present in results
- Be concise but complete; flag anything non-healthy
```

---

## Step 4: Return the Report

When the background task completes (you will receive a notification), retrieve the output with **TaskOutput** and present the full health report to the user.
