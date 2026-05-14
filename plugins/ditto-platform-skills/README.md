# ditto-platform-skills

SRE and platform engineering skills for Ditto infrastructure workflows.

## Skills

| Skill | Description |
|-------|-------------|
| `clusterhealth` | Check Kubernetes cluster health or list available clusters. Runs the resource scan as a background task and returns a full health report. Requires a mgmt or ops kubectl context. |
| `pr-review` | Review a pull request with a structured 3-section report (does it work / test coverage / code smells). Saves report to disk, with optional security review and PR comment posting. |
| `create-subtask` | Create a Linear sub-ticket linked to a parent issue, auto-assigned to the current user and set to In Progress. Checks Linear auth before proceeding. |
| `metrics-flow` | Report Prometheus ingestion rate, remote write rate, queue status, lag, and flow balance for the Vector pipeline. Discovers the Prometheus pod dynamically. |
