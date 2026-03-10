# How to Create the Ditto v5 Migration Custom GPT

## Prerequisites

- A ChatGPT account with GPT-4 access (Plus, Team, or Enterprise)

## Step-by-Step Setup

### 1. Open the GPT Builder

1. Go to [chat.openai.com](https://chat.openai.com)
2. In the left sidebar, click **Explore GPTs**
3. Click **Create** in the top-right corner

### 2. Configure the GPT

Click the **Configure** tab (not "Create" — that's the AI-guided wizard).

Fill in:

- **Name**: `Ditto v5 Migration Assistant`
- **Description**: `Expert assistant for migrating Ditto SDK apps from v4.14 to v5.0. Covers Swift, Kotlin, C++, Rust, Flutter, JavaScript, .NET, and Go.`
- **Instructions**: Paste the entire contents of `system-prompt.md` here
- **Conversation starters** (optional, add these for quick access):
  - `Help me migrate my Swift app from Ditto v4 to v5`
  - `How do I update Kotlin imports for Ditto v5?`
  - `Convert this Query Builder code to DQL`
  - `What changed in Ditto v5 for .NET?`

### 3. Enable Capabilities

Under **Capabilities**, enable:
- ✅ **Code Interpreter** — for analyzing and transforming code files
- ✅ **Web Search** (if available) — allows fetching latest Ditto docs

### 4. Upload Knowledge Files (Optional)

For best results, upload the migration guide files as knowledge:

1. Under **Knowledge**, click **Upload files**
2. Upload from the `plugins/ditto-v5-migration/skills/` directory:
   - `migrate-swift/SKILL.md`
   - `migrate-kotlin/SKILL.md`
   - `migrate-cpp/SKILL.md`
   - `migrate-rust/SKILL.md`
   - `migrate-flutter/SKILL.md`
   - `migrate-js/SKILL.md`
   - `migrate-dotnet/SKILL.md`
   - `migrate-go/SKILL.md`

### 5. Save and Test

1. Click **Save** (top right) — choose **Only me** for private use or **Anyone with link** to share
2. Start a conversation and test:
   ```
   I have this Swift code using Ditto v4. Can you update it to v5?

   let ditto = Ditto(identity: .onlinePlayground(appID: "my-id", enableDittoCloudSync: true))
   try? ditto.startSync()
   ```

### 6. Share (Optional)

To share with your team:
1. In the GPT settings, change visibility to **Anyone with link** or **Everyone**
2. Copy the GPT link and share with developers

## Tips

- **Code files**: If a developer uploads a source file, the GPT with Code Interpreter can read and transform it
- **Context**: Tell it the specific platform (e.g., "I'm working on a Kotlin Android app") for more accurate responses
- **Checklists**: Ask for the migration checklist for your platform to get a step-by-step task list

## Updating the GPT

When Ditto releases new SDK versions, update the instructions by:
1. Opening the GPT editor
2. Updating the **Instructions** field with a new system prompt
3. Re-uploading knowledge files if they've changed
