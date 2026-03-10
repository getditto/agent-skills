# Ditto v5 Migration Skills for AI Assistants

This directory contains skills and system prompts for AI assistants other than Claude Code, enabling them to help developers migrate Ditto SDK applications from v4.14 to v5.0.

## Available Platforms

| Directory | Platform | Format |
|-----------|----------|--------|
| [chatgpt/](./chatgpt/) | ChatGPT | Custom GPT instructions |
| [gemini/](./gemini/) | Google Gemini | Gemini Gem instructions |

## What These Skills Cover

Each platform's skill provides the AI with knowledge to:

1. **Universal v4→v5 changes** across all platforms
2. **Per-platform specifics**: Swift, Kotlin, C++, Rust, Flutter, JavaScript, .NET, Go
3. **DQL migration**: Translating legacy Query Builder patterns to DQL
4. **Critical warnings**: DQL_STRICT_MODE default change, WebSocket sync default, persistence directory change
5. **Migration checklists** per platform

## For Claude Code Users

If you use Claude Code, see the [ditto-v5-migration plugin](../plugins/ditto-v5-migration/) instead — it provides per-platform skills with more context and code examples.

Install with:
```bash
/plugin install ditto-v5-migration
```
