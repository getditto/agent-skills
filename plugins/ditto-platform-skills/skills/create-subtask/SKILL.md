---
name: create-subtask
description: Create a Linear sub-ticket linked to a parent issue. Use when the user asks to create a sub-ticket, sub-task, or child issue for a Linear ticket (e.g. "create a sub-ticket for SRE-123").
allowed-tools: mcp__linear__get_issue, mcp__linear__get_issue_status, mcp__linear__save_issue, mcp__linear__get_user, mcp__linear__list_teams
---

# Create Linear Sub-Ticket

Creates a sub-ticket linked to a parent Linear issue, assigned to the current user and set to In Progress.

## Step 1: Verify Linear Authentication

Call the Linear MCP to fetch the current authenticated user:
```
mcp__linear__list_teams (limit: 1)
```

If this call fails or returns an authentication error, respond:
> "You're not signed into Linear. Please authenticate via the Linear MCP connection and try again."

Stop here if the auth check fails.

## Step 2: Get Parent Issue Details

Using the parent issue ID provided by the user (e.g. `SRE-123`), fetch the issue:
```
mcp__linear__get_issue (issueId: "<parent-id>")
```

Extract:
- `id` — parent issue UUID (for `parentId`)
- `team.id` — team UUID (for `teamId`)
- `project.id` — project UUID (for `projectId`)

If the issue is not found, respond:
> "Could not find issue <parent-id>. Check the issue ID and try again."

## Step 3: Resolve "In Progress" Status

Look up the In Progress status ID for the team:
```
mcp__linear__get_issue_status (query: "In Progress", teamId: "<team-id>")
```

Extract the `id` of the matching status for use as `stateId`.

## Step 4: Get Current User ID

Fetch the authenticated user's ID to assign the sub-ticket:
```
mcp__linear__get_user (userId: "me")
```

Extract the `id` for use as `assigneeId`.

## Step 5: Create the Sub-Ticket

Create the sub-issue with all resolved IDs:
```
mcp__linear__save_issue (
  title: "<title provided by user>",
  parentId: "<parent issue UUID>",
  teamId: "<team UUID>",
  projectId: "<project UUID>",
  stateId: "<In Progress status UUID>",
  assigneeId: "<current user UUID>"
)
```

## Step 6: Confirm

Once created, respond with the new issue ID and a link:
> "Created <new-issue-id>: '<title>' as a sub-ticket of <parent-id>, assigned to you and set to In Progress."
