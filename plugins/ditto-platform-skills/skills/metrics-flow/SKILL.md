---
name: metrics-flow
description: Report current Prometheus metrics flow — ingestion rate, remote write rate, queue status, lag, and flow balance. Use when user asks about metrics flow, Prometheus performance, remote write health, or Vector pipeline status.
allowed-tools: Bash, Task, TaskCreate, TaskOutput, TaskGet
---

# Metrics Flow Analysis

Reports the current state of the Prometheus remote write pipeline for a workload cluster. Runs in the background so the conversation stays responsive.

## Step 1: Resolve kubectl Context

Get the current context:
```bash
kubectl config current-context
```

Set `CONTEXT` to the current context and use `--context <CONTEXT>` on every kubectl command below.

If the current context is a management context (contains `mgmt-`), it won't have a workload Prometheus. List available non-mgmt contexts and ask the user to pick one:
```bash
kubectl config get-contexts --no-headers -o name | grep -v "mgmt-"
```

Wait for the user's selection before proceeding.

## Step 2: Spawn Background Analysis

Tell the user:
> "Running metrics flow analysis for `<CONTEXT>` in the background — I'll report back when it's done."

Use the **Task tool** with `run_in_background: true`, passing the prompt below (substituting the resolved context for `<CONTEXT>`):

---

```
Run a Prometheus metrics flow analysis using kubectl context <CONTEXT>.
Use --context <CONTEXT> on every kubectl command below.

## Discover the Prometheus Pod

Locate the Prometheus pod in `monitoring-system` first (the ArgoCD-managed stack):
  kubectl get pod -n monitoring-system --context <CONTEXT> -l "app.kubernetes.io/name=prometheus" --no-headers -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name" | head -1

If not found, try a broader search across all namespaces:
  kubectl get pod -A --context <CONTEXT> -l "app.kubernetes.io/name=prometheus" --no-headers -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name" | head -1

If still not found:
  kubectl get pod -A --context <CONTEXT> -l "app=prometheus" --no-headers -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name" | head -1

Extract NAMESPACE and POD_NAME. Use `kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT>` for all subsequent exec commands.

If no pod is found, return: "Could not find a running Prometheus pod in context <CONTEXT>." and stop.

## Discover Remote Write Targets

Query Prometheus for all configured remote write targets:
  kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT> -- wget -O- -q 'http://localhost:9090/api/v1/query?query=prometheus_remote_storage_samples_total'

Parse the `remote_name` label values. If no results are returned, note that remote write may not be active yet (e.g. Prometheus just restarted).

## Run Queries

Run all of the following. Repeat per-target queries for every discovered remote_name.

Incoming rate:
  kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT> -- wget -O- -q "http://localhost:9090/api/v1/query?query=rate(prometheus_tsdb_head_samples_appended_total[1m])"

Outgoing rate per target:
  kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT> -- wget -O- -q 'http://localhost:9090/api/v1/query?query=rate(prometheus_remote_storage_samples_total{remote_name="<TARGET>"}[1m])'

Pending queue per target:
  kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT> -- wget -O- -q 'http://localhost:9090/api/v1/query?query=prometheus_remote_storage_samples_pending{remote_name="<TARGET>"}'

Queue trend per target:
  kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT> -- wget -O- -q 'http://localhost:9090/api/v1/query?query=deriv(prometheus_remote_storage_samples_pending{remote_name="<TARGET>"}[2m])'

Lag per target:
  kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT> -- wget -O- -q 'http://localhost:9090/api/v1/query?query=time()-prometheus_remote_storage_queue_highest_sent_timestamp_seconds{remote_name="<TARGET>"}'

Active series:
  kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT> -- wget -O- -q "http://localhost:9090/api/v1/query?query=prometheus_tsdb_head_series"

Success rate per target:
  kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT> -- wget -O- -q 'http://localhost:9090/api/v1/query?query=(rate(prometheus_remote_storage_samples_total{remote_name="<TARGET>"}[1m])-rate(prometheus_remote_storage_samples_failed_total{remote_name="<TARGET>"}[1m]))/rate(prometheus_remote_storage_samples_total{remote_name="<TARGET>"}[1m])*100'

## Present the Report

Format the results as (repeat the per-target section for each remote write target):

```
METRICS FLOW ANALYSIS — <cluster-name>
========================================
Pod: <NAMESPACE>/<POD_NAME>

INCOMING (Scraped):  <N> samples/sec

── Remote Write: <TARGET NAME> ──────────
OUTGOING:   <N> samples/sec
PENDING:    <N> samples
TREND:      Growing / Draining / Stable at <N> samples/sec
LAG:        <N> seconds  [Healthy / Degraded / Critical]
SUCCESS:    <N>%
FLOW:       Balanced / ⚠️ Incoming exceeds outgoing / Queue draining

(repeat for each additional target)

SCALE:
  Active series: <N>
  Per minute:    <N>
  Per hour:      <N>
  Per day:       <N>
```

Lag thresholds:
- < 30s → Healthy
- 30–120s → Degraded — monitor closely
- > 120s → Critical — remote write is significantly behind

Flow balance:
- IN ≈ OUT → Balanced
- IN > OUT → Warning — queue will grow
- OUT > IN → Queue draining — catching up after backlog
```

---

## Step 3: Return the Report

When the background task completes (you will receive a notification), retrieve the output with **TaskOutput** and present the full metrics report to the user.
