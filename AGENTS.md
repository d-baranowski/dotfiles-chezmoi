# AGENTS.md

This repository contains dotfiles managed by [chezmoi](https://www.chezmoi.io/). This file provides instructions for AI coding agents working in this repo.

## Key concept

This is NOT a normal config directory. Files here are **source templates** that chezmoi renders and copies to the user's home directory. The naming conventions encode metadata (permissions, file paths, templating).

## File naming rules

| Prefix/Suffix | Meaning | Example |
|---------------|---------|---------|
| `dot_` | Becomes `.` in target path | `dot_zshrc` → `~/.zshrc` |
| `private_` | Sets restrictive permissions (0700/0600) | `private_dot_ssh/` → `~/.ssh/` |
| `executable_` | Sets execute bit | `executable_sketchybarrc` → `sketchybarrc` (chmod +x) |
| `.tmpl` suffix | Go template, rendered before writing | `mcp_config.json.tmpl` → `mcp_config.json` |

These compose: `private_dot_config/sketchybar/executable_sketchybarrc` → `~/.config/sketchybar/sketchybarrc` (private dir, executable file).

## Editing workflow

```bash
# Find the source file for a dotfile
chezmoi source-path ~/.zshrc

# Edit the source (NOT the actual dotfile)
chezmoi edit ~/.zshrc

# Preview what would change
chezmoi diff

# Apply to home directory
chezmoi apply -v
```

**Always edit source files in this repo, then apply. Never edit `~/.zshrc`, `~/.tmux.conf`, etc. directly.**

If a file was edited directly (by an app or manually), pull it back:
```bash
chezmoi add ~/.config/karabiner/karabiner.json
```

## Secrets

Secrets live in `.chezmoidata.yaml` (gitignored). Templates reference them as `{{ .variable_name }}`.

Current secrets:
- `mcpproxy_api_key` — MCPProxy Web UI API key
- `postgres_password` — local PostgreSQL password

To add a new secret:
1. Add the variable to `.chezmoidata.yaml`
2. Add a placeholder to `.chezmoidata.yaml.example`
3. Reference it in the template as `{{ .new_secret }}`

Machine-specific values like home directory use `{{ .chezmoi.homeDir }}` — never hardcode `/Users/danielbaranowski`.

## What is excluded

These are gitignored or chezmoiignored and should never be added:
- `.chezmoidata.yaml` (secrets)
- `~/.tmux/plugins/` (managed by TPM)
- `~/.oh-my-zsh/custom/plugins/` (managed by oh-my-zsh)
- SSH keys, AWS/GCloud credentials, SOPS/age keys, Kubernetes configs

## Do not

- Commit secrets, API keys, tokens, or private keys to any file
- Edit target dotfiles directly — always edit the chezmoi source
- Hardcode the home directory path — use `{{ .chezmoi.homeDir }}`
- Add third-party plugin directories (tmux plugins, oh-my-zsh plugins)
- Remove the `.tmpl` suffix from template files
