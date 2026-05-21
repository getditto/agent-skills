---
name: teleport-agent-debug
description: Debug Teleport Kubernetes agent health on a cluster. Check tsh login state, list accessible clusters for selection, inspect teleport-system (or legacy teleport) namespace pods for OOM kills, CPU/memory pressure, and error logs. Use when Teleport connectivity is degraded, agents are restarting, or cluster access is failing.
allowed-tools: Bash, Task, TaskCreate, TaskOutput, TaskGet
---

# Teleport Agent Debug

Diagnoses Teleport Kubernetes agent health on a target cluster. Runs the resource and log scan as a background task so the conversation stays responsive.

## Step 1: Check Teleport Login State

```bash
tsh status
```

If the output indicates the user is not logged in or returns an error, tell the user:
> "You're not logged in to Teleport. Run: `tsh login --proxy=ditto.teleport.sh --auth=okta`"

Stop here.

If logged in, extract and report:
- Proxy address
- Logged-in username
- Credential expiry time

## Step 2: List Clusters and Select Target

```bash
tsh kube ls
```

Display the full cluster list as a numbered table. Ask:
> "Which cluster would you like to diagnose?"

Wait for the user's selection. Set `CLUSTER` to the chosen cluster name.

Now check whether a matching kubectl context already exists for that cluster:

```bash
kubectl config get-contexts --no-headers -o name | grep "<CLUSTER>"
```

If a matching context is found, set `CONTEXT` to it and proceed to Step 3.

If no matching context is found, display this command for the user to run manually:

```
tsh kube login <CLUSTER>
```

Tell the user:
> "No kubectl context found for `<CLUSTER>`. Run the command above, then re-run this skill."

Stop here.

## Step 3: Identify Teleport Agent Namespace

Check for the modern namespace first:

```bash
kubectl get namespace teleport-system --context <CONTEXT> --no-headers 2>/dev/null
```

If found, set `NS=teleport-system` and proceed to Step 4.

Otherwise check the legacy namespace:

```bash
kubectl get namespace teleport --context <CONTEXT> --no-headers 2>/dev/null
```

If found, set `NS=teleport` and proceed to Step 4.

If neither exists, respond:
> "Neither `teleport-system` nor `teleport` namespace found on `<CLUSTER>`. Teleport agents may not be deployed here."

Stop here.

## Step 4: Spawn Background Diagnostic

Tell the user:
> "Running Teleport agent diagnostics for `<CLUSTER>` (namespace: `<NS>`) in the background — I'll report back when it's done."

Use the **Task tool** with `run_in_background: true`, passing the prompt below. Substitute the real cluster name for `<CLUSTER>`, resolved namespace for `<NS>`, and kubectl context for `<CONTEXT>`:

---

```
Run a Teleport agent health diagnostic in namespace <NS> using kubectl context <CONTEXT>.
Use --context <CONTEXT> on every kubectl command.

### Agent Pod Overview

List all pods and their status:
  kubectl get pods -n <NS> --context <CONTEXT> -o wide

### Pod Details

For each agent pod found, describe it to surface OOMKilled history, restart counts, and resource limits/requests:
  kubectl describe pod <POD_NAME> -n <NS> --context <CONTEXT>

In the describe output, look for:
- Last State: OOMKilled → flag CRITICAL
- Restart count > 5 → flag HIGH
- Missing resource limits → flag MEDIUM
- Liveness/readiness probe failures → flag HIGH

### Resource Usage

Check live CPU and memory against limits:
  kubectl top pod -n <NS> --context <CONTEXT>

If usage exceeds 80% of limit for any pod, flag it.
If kubectl top is unavailable (metrics-server not present), note that and skip.

### Recent Events

Check namespace events for OOM, eviction, and backoff signals:
  kubectl get events -n <NS> --context <CONTEXT> --sort-by='.lastTimestamp' | tail -30

Flag: OOMKilling, Evicted, BackOff, FailedMount, Failed events.

### Agent Logs

Collect recent logs from each agent pod (last 150 lines):
  kubectl logs -n <NS> <POD_NAME> --context <CONTEXT> --tail=150

If the pod has multiple containers, check each:
  kubectl logs -n <NS> <POD_NAME> -c <CONTAINER> --context <CONTEXT> --tail=100

Scan for:
- "error" / "ERR" / "Error" lines
- "failed to connect" / "connection refused"
- "certificate" / "TLS" errors
- "auth" / "unauthorized" failures
- "context deadline exceeded"
- "dial" failures

### Report

Produce this structured report:

TELEPORT AGENT DIAGNOSTIC — <CLUSTER>
======================================
Namespace:  <NS>
Context:    <CONTEXT>

AGENTS (<count> pods)
─────────────────────
<pod-name>
  Status:     Running | CrashLoopBackOff | Pending | etc.
  Restarts:   <N>
  OOMKilled:  Yes / No
  CPU:        <usage> / <limit>   [OK / ⚠ HIGH / ✗ CRITICAL]
  Memory:     <usage> / <limit>   [OK / ⚠ HIGH / ✗ CRITICAL]

(repeat for each pod)

LOG ERRORS
──────────
<pod-name>:
  [timestamp] <error line>
  [timestamp] <error line>
  (or "No errors found")

EVENTS
──────
<recent warning events with timestamp and message>
(or "No warning events in the last recorded events")

ISSUES REQUIRING ATTENTION
──────────────────────────
Severity | Issue                 | Detail
-------- | --------------------- | -------
CRITICAL | OOMKilled             | <pod> was OOMKilled; increase memory limit
HIGH     | High restart count    | <pod> restarted <N> times
HIGH     | Probe failures        | Liveness probe failing on <pod>
MEDIUM   | Memory near limit     | <pod> at <N>% of memory limit
MEDIUM   | Missing limits        | <pod> has no resource limits set
LOW      | Auth errors in log    | "connection refused" to proxy <addr>

If no issues are found: "All Teleport agents appear healthy."
```

---

## Step 5: Return the Report

When the background task completes (you will receive a notification), retrieve the output with **TaskOutput** and present the full diagnostic report to the user.
