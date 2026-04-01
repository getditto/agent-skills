# Skills for Other AI Assistants

This directory contains skills and system prompts for AI assistants **other than Claude Code**. If you use Claude Code, install the plugins from the [plugins/](../plugins/) directory instead.

These skills package the same domain knowledge as the Claude Code plugins but in formats compatible with other AI tools.

## Available Skills

| Directory | AI Assistant | Content |
|-----------|-------------|---------|
| [chatgpt/](./chatgpt/) | ChatGPT (Custom GPT) | Ditto v5 migration assistant |
| [gemini/](./gemini/) | Google Gemini (Gem) | Ditto v5 migration assistant |

## How to Use

Each subdirectory contains:

- **`system-prompt.md`** — The complete instructions to paste into your AI assistant's configuration
- **`instructions.md`** — Step-by-step setup guide for that platform
- **`README.md`** — Quick-start overview

Follow the README in each subdirectory for platform-specific setup steps.

## Adding Skills for Other Platforms

To contribute skills for an additional AI assistant (e.g., Copilot, Cursor, Windsurf):

1. Create a new subdirectory under `skills/` named after the platform
2. Include a `system-prompt.md` with the full instructions
3. Include an `instructions.md` with setup steps
4. Include a `README.md` with a quick-start guide
5. Update this README's table above
6. Submit a pull request
