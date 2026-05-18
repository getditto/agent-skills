---
description: Compile a structured Ditto SDK or Big Peer problem report (new report) OR update an existing report by adding logs, devices, or other details. Produces a Markdown file or .zip bundle. Use $ARGUMENTS as the initial problem statement, an existing report path, or an "update" hint.
---

Load the `compile-ditto-problem-report` skill and run its workflow.

**Mode detection — do this first:**

- If $ARGUMENTS contains the literal word `update`, `add`, `amend`, or a path matching `ditto-problem-report-*.md` or `ditto-problem-report-*.zip`, treat this as **update mode**: locate the target report (use the explicit path if given, otherwise glob the current directory) and run the skill's "Update mode (modifying an existing report)" flow.
- Otherwise, treat $ARGUMENTS as the user's initial problem statement for a new report and run the normal interview flow.
- If $ARGUMENTS is empty, follow the skill's Mode detection rules (glob the current directory and ask if ambiguous).

**For both modes:**

- Extract whatever you can from $ARGUMENTS (summary, SDK + version, OS, regression hints, log paths) and don't re-ask for inferred values.
- Follow the skill's audience-detection step (check `git config user.email` for `@ditto.com`).
- For internal users, offer the Linear-issue path at the end via the `linear-server` MCP — file a new issue, comment on a duplicate, or post the delta as a comment on a previously-filed Linear issue (update mode). For external users, instruct them to send the result to support@ditto.com.

End your response with the absolute path of the final artifact (the `.md` file or the `.zip` bundle). If an update promoted a `.md` to a `.zip`, make the path change explicit.
