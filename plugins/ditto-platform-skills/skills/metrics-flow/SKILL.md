---
name: metrics-flow
description: Report current Prometheus metrics flow — ingestion rate, remote write rate, queue status, lag, and flow balance. Use when user asks about metrics flow, Prometheus performance, remote write health, or Vector pipeline status.
allowed-tools: Bash
---

# Metrics Flow Analysis

Reports the current state of the Prometheus remote write pipeline for a workload cluster.

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

## Step 2: Discover the Prometheus Pod

Locate the Prometheus pod in `monitoring-system` first (the ArgoCD-managed stack):
```bash
kubectl get pod -n monitoring-system --context <CONTEXT> \
  -l "app.kubernetes.io/name=prometheus" --no-headers \
  -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name" | head -1
```

If not found, try a broader search across all namespaces:
```bash
kubectl get pod -A --context <CONTEXT> \
  -l "app.kubernetes.io/name=prometheus" --no-headers \
  -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name" | head -1
```

If still not found:
```bash
kubectl get pod -A --context <CONTEXT> \
  -l "app=prometheus" --no-headers \
  -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name" | head -1
```

Extract `NAMESPACE` and `POD_NAME`. All subsequent `kubectl exec` commands use:
```
kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT>
```

If no pod is found, respond:
> "Could not find a running Prometheus pod in context `<CONTEXT>`. Check your kubectl context and try again."

## Step 3: Discover Remote Write Targets

Query Prometheus for all configured remote write targets rather than assuming a name:
```bash
kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT> -- \
  wget -O- -q 'http://localhost:9090/api/v1/query?query=prometheus_remote_storage_samples_total'
```

Parse the `remote_name` label values from the result. If no results are returned, the remote write pipeline may not be active yet (e.g. Prometheus just restarted) — note this in the report.

## Step 4: Run the Metrics Flow Analysis

Run the following queries. For each query that filters by `remote_name`, repeat it for every discovered target.

**Incoming rate** (samples scraped from targets):
```bash
kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT> -- \
  wget -O- -q "http://localhost:9090/api/v1/query?query=rate(prometheus_tsdb_head_samples_appended_total[1m])"
```

**Outgoing rate** per remote write target:
```bash
kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT> -- \
  wget -O- -q 'http://localhost:9090/api/v1/query?query=rate(prometheus_remote_storage_samples_total{remote_name="<TARGET>"}[1m])'
```

**Pending queue size** per target:
```bash
kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT> -- \
  wget -O- -q 'http://localhost:9090/api/v1/query?query=prometheus_remote_storage_samples_pending{remote_name="<TARGET>"}'
```

**Queue trend** per target (positive = growing, negative = draining):
```bash
kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT> -- \
  wget -O- -q 'http://localhost:9090/api/v1/query?query=deriv(prometheus_remote_storage_samples_pending{remote_name="<TARGET>"}[2m])'
```

**Lag** per target (seconds behind current time):
```bash
kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT> -- \
  wget -O- -q 'http://localhost:9090/api/v1/query?query=time()-prometheus_remote_storage_queue_highest_sent_timestamp_seconds{remote_name="<TARGET>"}'
```

**Active series count**:
```bash
kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT> -- \
  wget -O- -q "http://localhost:9090/api/v1/query?query=prometheus_tsdb_head_series"
```

**Remote write success rate** per target:
```bash
kubectl exec -n <NAMESPACE> <POD_NAME> -c prometheus --context <CONTEXT> -- \
  wget -O- -q 'http://localhost:9090/api/v1/query?query=(rate(prometheus_remote_storage_samples_total{remote_name="<TARGET>"}[1m])-rate(prometheus_remote_storage_samples_failed_total{remote_name="<TARGET>"}[1m]))/rate(prometheus_remote_storage_samples_total{remote_name="<TARGET>"}[1m])*100'
```

## Step 5: Present the Report

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

**Lag thresholds:**
- < 30s → Healthy
- 30–120s → Degraded — monitor closely
- > 120s → Critical — remote write is significantly behind

**Flow balance:**
- IN ≈ OUT → Balanced
- IN > OUT → Warning — queue will grow
- OUT > IN → Queue draining — catching up after backlog
