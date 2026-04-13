---
name: ksave
description: Save knowledge context to the Obsidian AI Knowledge Base
allowed-tools: Bash Read Write Glob Grep
---

# Save Knowledge to Obsidian

Save useful context from this conversation to the AI Knowledge Base in Obsidian.

**Vault path:** `~/Documents/obsidian/work-notes/work-notes/AI Knowledge Base/`

## Arguments

Usage: `/ksave [folder/title]` or `/ksave` (interactive)

- If `$ARGUMENTS` is provided, parse it as `folder/title` (e.g., `dotfiles/Sketchybar Plugins`)
- If only a title is given (no `/`), use the current project directory name as the folder
- If no arguments, ask the user what to save and where

## Steps

1. Determine the folder and title from arguments or by asking the user
2. Create the folder under the AI Knowledge Base path if it doesn't exist: `mkdir -p "$KB_PATH/$FOLDER"`
3. Synthesize the relevant knowledge from the current conversation into a clean, useful markdown document:
   - Use clear headings and structure
   - Include code snippets, commands, and config examples where relevant
   - Focus on **reusable knowledge** — not a conversation transcript
   - Add a metadata header with date and source project
   - Keep it concise but complete enough to be useful without the original conversation
4. Write the file to `~/Documents/obsidian/work-notes/work-notes/AI Knowledge Base/$FOLDER/$TITLE.md`
5. Confirm what was saved and where

## Output Format

The saved markdown file should start with:

```markdown
# {Title}

> Project: {current project or context}
> Saved: {YYYY-MM-DD}
> Tags: {relevant tags}

{content}
```
