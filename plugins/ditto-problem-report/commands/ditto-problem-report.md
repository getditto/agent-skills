---
description: Compile a structured Ditto SDK or Big Peer problem report from an interview, producing a Markdown file (or a .zip bundle when logs/attachments are supplied). Use $ARGUMENTS as the initial problem statement.
---

Load the `compile-ditto-problem-report` skill and run its workflow to produce a Ditto problem report in the current directory.

If $ARGUMENTS is non-empty, treat it as the user's initial problem statement — extract whatever fields you can from it (summary, SDK + version, OS, regression hints, log paths) and skip asking about anything already provided. Only interview the user for the remaining required fields listed in the skill.

If $ARGUMENTS is empty, start the interview from scratch.

Follow the skill's audience-detection step early (check `git config user.email` for `@ditto.com`). For internal users, offer the Linear-issue path at the end via the `linear-server` MCP. For external users, instruct them to send the result to support@ditto.com.

End your response with the absolute path of the final artifact (the `.md` file or the `.zip` bundle).
