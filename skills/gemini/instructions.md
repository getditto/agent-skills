# How to Create the Ditto v5 Migration Gemini Gem

## Prerequisites

- A Google account
- Access to Gemini Advanced (Google One subscription) for custom Gems

## Step-by-Step Setup

### 1. Open the Gems Manager

1. Go to [gemini.google.com](https://gemini.google.com)
2. In the left sidebar, click **Gems**
3. Click **New Gem** (+ button)

### 2. Configure the Gem

Fill in the following:

- **Name**: `Ditto v5 Migration Assistant`
- **Instructions**: Paste the entire contents of `system-prompt.md` here

### 3. Save the Gem

Click **Save** to create the Gem.

### 4. Test the Gem

Click on your new Gem to open a conversation and test:

```
I'm working on a Kotlin Android app using Ditto v4. Can you show me
how to update the initialization code to v5?

val ditto = Ditto(
    DefaultAndroidDittoDependencies(context),
    DittoIdentity.OnlinePlayground(
        dependencies = androidDependencies,
        appId = "my-app-id",
        token = "my-token"
    )
)
ditto.startSync()
```

### 5. Share the Gem (Optional)

Currently, Gemini Gems are personal and cannot be directly shared. Each developer on your team would need to create their own Gem by following these steps.

For team distribution, you can:
- Share this repository with the `system-prompt.md` file
- Include setup instructions in your team's onboarding docs

## Tips

- **Be specific about platform**: Start messages with "I'm working on a Swift/Kotlin/C++ app" for more accurate responses
- **Paste code snippets**: Gemini can read and transform pasted code directly
- **Ask for checklists**: "Give me the migration checklist for Flutter" returns a full step-by-step list
- **Chain requests**: "Now update all the observers in this file" after an initial migration

## Gemini vs Gemini Advanced

| Feature | Gemini | Gemini Advanced |
|---------|--------|-----------------|
| Custom Gems | ❌ | ✅ |
| Longer context | Limited | Expanded |
| Code understanding | Good | Better |

Custom Gems require **Gemini Advanced** (Google One AI Premium). For Gemini without Advanced, paste the system prompt directly at the start of a conversation.

## Alternative: Direct Conversation Setup

If you don't have Gemini Advanced, start any Gemini conversation with:

```
You are an expert Ditto SDK migration assistant. [Paste system-prompt.md content here]

Now help me with: [your migration question]
```

## Updating the Gem

When Ditto releases new SDK versions:
1. Open the Gem editor (Gems → click ⋮ → Edit)
2. Update the **Instructions** with the new system prompt
3. Save the Gem
