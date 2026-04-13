---
name: kload
description: Load a knowledge base entry from Obsidian into the conversation
allowed-tools: Bash Read Glob Grep
---

# Load Knowledge from Obsidian

Load a saved knowledge base entry into the current conversation context.

**Vault path:** `~/Documents/obsidian/work-notes/work-notes/AI Knowledge Base/`

## Arguments

Usage: `/kload [folder/title]` or `/kload [search term]`

## Steps

1. If `$ARGUMENTS` matches a file path directly (with or without `.md` extension):
   - Read `~/Documents/obsidian/work-notes/work-notes/AI Knowledge Base/$ARGUMENTS.md` (append .md if needed)
   - Present the full contents

2. If the exact path doesn't exist, treat `$ARGUMENTS` as a fuzzy search:
   - Search file names under the AI Knowledge Base for the closest match
   - If one match: load it directly
   - If multiple matches: list them and ask which one to load
   - If no matches: say so and suggest `/ksearch` to browse

3. If no `$ARGUMENTS`:
   - List all available entries (like `/ksearch` with no args)
   - Ask which one to load

4. After loading, briefly summarize what context was loaded so the user knows it's available for the rest of the conversation.
