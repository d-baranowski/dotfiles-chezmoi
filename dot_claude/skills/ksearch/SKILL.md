---
name: ksearch
description: Search the Obsidian AI Knowledge Base for saved context
allowed-tools: Bash Read Glob Grep
---

# Search AI Knowledge Base

Search through saved knowledge in the Obsidian AI Knowledge Base.

**Vault path:** `~/Documents/obsidian/work-notes/work-notes/AI Knowledge Base/`

## Arguments

Usage: `/ksearch [query]` or `/ksearch` (lists all entries)

## Steps

1. If no `$ARGUMENTS` provided:
   - List all folders and files in the AI Knowledge Base with a tree view
   - Show file titles and their first-line descriptions
   - Present as a numbered list so the user can pick one to load

2. If `$ARGUMENTS` is a search query:
   - Search **file names** (glob) and **file contents** (grep) under the AI Knowledge Base path
   - Match against `*.md` files only
   - Show results grouped by folder with matching context snippets
   - If few results, show a brief preview of each match

3. Present results clearly:
   - Show relative path from the AI Knowledge Base root
   - Show the first few lines or the matching section
   - Suggest `/kload folder/filename` to load any result

## Output Format

```
📂 AI Knowledge Base
├── 📁 dotfiles/
│   └── Dotfiles Chezmoi Setup.md — Full chezmoi dotfiles context
├── 📁 kubernetes/
│   └── Cluster Setup Notes.md — K8s cluster configuration
...

Found N entries. Use /kload <folder/title> to load one.
```
