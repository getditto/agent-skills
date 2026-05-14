---
name: metrics-flow
description: Report current Prometheus metrics flow — ingestion rate, remote write rate, queue status, lag, and flow balance. Use when user asks about metrics flow, Prometheus performance, remote write health, or Vector pipeline status.
allowed-tools: Bash
---

# Metrics Flow Analysis

Reports the current state of the Prometheus → Vector remote write pipeline.

## Step 1: Discover the Prometheus Pod

Dynamically locate the Prometheus pod and its namespace rather than relying on a hardcoded name:

```bash
kubectl get pod -A -l "app.kubernetes.io/name=prometheus" --no-headers \
  -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name" | head -1
```

If no pod is found, try the broader label:
```bash
kubectl get pod -A -l "app=prometheus" --no-headers \
  -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name" | head -1
```

Extract the namespace and pod name. All subsequent `kubectl exec` commands use these values as `-n <namespace> <pod-name> -c prometheus`.

If no Prometheus pod can be found, respond:
> "Could not find a running Prometheus pod. Check your kubectl context and try again."

## Step 2: Run the Metrics Flow Analysis

Execute all queries against the discovered pod. Run them and collect the results:

**Incoming rate** (samples scraped from targets):
```bash
kubectl exec -n <namespace> <pod-name> -c prometheus -- \
  wget -O- -q "http://localhost:9090/api/v1/query?query=rate(prometheus_tsdb_head_samples_appended_total[1m])"
```

**Outgoing rate** (samples sent via remote write to Vector):
```bash
kubectl exec -n <namespace> <pod-name> -c prometheus -- \
  wget -O- -q 'http://localhost:9090/api/v1/query?query=rate(prometheus_remote_storage_samples_total{remote_name="vector-agg"}[1m])'
```

**Pending queue size**:
```bash
kubectl exec -n <namespace> <pod-name> -c prometheus -- \
  wget -O- -q 'http://localhost:9090/api/v1/query?query=prometheus_remote_storage_samples_pending{remote_name="vector-agg"}'
```

**Queue trend** (positive = growing, negative = draining):
```bash
kubectl exec -n <namespace> <pod-name> -c prometheus -- \
  wget -O- -q 'http://localhost:9090/api/v1/query?query=deriv(prometheus_remote_storage_samples_pending{remote_name="vector-agg"}[2m])'
```

**Lag** (seconds behind current time):
```bash
kubectl exec -n <namespace> <pod-name> -c prometheus -- \
  wget -O- -q 'http://localhost:9090/api/v1/query?query=time()-prometheus_remote_storage_queue_highest_sent_timestamp_seconds{remote_name="vector-agg"}'
```

**Active series count**:
```bash
kubectl exec -n <namespace> <pod-name> -c prometheus -- \
  wget -O- -q "http://localhost:9090/api/v1/query?query=prometheus_tsdb_head_series"
```

**Remote write success rate**:
```bash
kubectl exec -n <namespace> <pod-name> -c prometheus -- \
  wget -O- -q 'http://localhost:9090/api/v1/query?query=(rate(prometheus_remote_storage_samples_total{remote_name="vector-agg"}[1m])-rate(prometheus_remote_storage_samples_failed_total{remote_name="vector-agg"}[1m]))/rate(prometheus_remote_storage_samples_total{remote_name="vector-agg"}[1m])*100'
```

## Step 3: Present the Report

Format the results as:

```
METRICS FLOW ANALYSIS
=====================

INCOMING (Scraped):    <N> samples/sec

OUTGOING (Remote Write): <N> samples/sec

QUEUE STATUS:
  Pending: <N> samples
  Trend:   Growing / Draining / Stable at <N> samples/sec
  Lag:     <N> seconds

SCALE:
  Active series: <N>
  Per minute:    <N> million
  Per hour:      <N> million
  Per day:       <N> billion

SUCCESS RATE: <N>%

FLOW: Balanced / Incoming exceeds outgoing by <N> samples/sec / Queue draining
```

**Flow balance interpretation:**
- IN ≈ OUT → Balanced — system is keeping up
- IN > OUT → Warning — queue will grow; remote write may be falling behind
- OUT > IN → Queue draining — catching up after a backlog

**Lag interpretation:**
- < 30s → Healthy
- 30–120s → Degraded — monitor closely
- \> 120s → Critical — remote write is significantly behind
