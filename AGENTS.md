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

## Hand-rolled tmux status pills (catppuccin)

`dot_tmux.conf.tmpl` contains hand-rolled status-bar pills (session, COPY, git) that need to visually match catppuccin's built-in modules. The spacing convention is non-obvious — get it wrong and pills look fatter than the built-in directory pill.

**Inspect the reference pill before changing anything.** The catppuccin directory module is the canonical reference; copy its structure exactly:

```bash
tmux show-options -gv @catppuccin_status_directory       | xxd
tmux show-options -gv @catppuccin_status_left_separator  | xxd  # 20 ee82b6 — leading space + glyph
tmux show-options -gv @catppuccin_status_right_separator | xxd  # ee82b4 20 — glyph + trailing space
tmux show-options -gv @catppuccin_directory_icon         | xxd  # ef81bb 20 — glyph + trailing space (icon-FIRST)
```

Rules for a pill that matches the directory module:

1. **No literal space before `#{E:@catppuccin_status_left_separator}`** — the separator already includes its own leading space.
2. **No literal space before `#{E:@catppuccin_status_right_separator}`** — same reason.
3. **The icon block is `<glyph><space>`, not `<space><glyph><space>`** — icon first, then one trailing space inside the colored bg.
4. **The text block starts with one leading space, no trailing space.** Right corner uses `fg=SURFACE_0` so the rounded shape closes the text bg.

Canonical pill template (mauve example):

```
#[fg=#{E:@thm_mauve}]#[bg=default]#{E:@catppuccin_status_left_separator}#[fg=#{E:@thm_crust},bg=#{E:@thm_mauve}]<ICON> #[fg=#{E:@thm_fg},bg=#{E:@thm_surface_0}]<TEXT>#[fg=#{E:@thm_surface_0}]#[bg=default]#{E:@catppuccin_status_right_separator}
```

### Editing files containing nerd-font (PUA) glyphs

The `Edit` tool can silently strip Unicode private-use-area characters (U+E000–U+F8FF), which is where every nerd-font icon lives. The diff will look correct but `xxd` will show the bytes are gone.

Workaround: write the glyph via a Python heredoc using `\uXXXX` escapes (keeps the source ASCII), then verify with `xxd`:

```bash
python3 <<'PY'
import pathlib
p = pathlib.Path('dot_tmux/executable_git-status.sh')
s = p.read_text()
p.write_text(s.replace('OLD', 'NEW \uf09b WITH GLYPH'))
PY
xxd dot_tmux/executable_git-status.sh | grep 'ef82 9b'  # confirm the bytes landed
```

### Git pill specifics

- Source: `dot_tmux/executable_git-status.sh` → `~/.tmux/git-status.sh`
- Wired in `dot_tmux.conf.tmpl` `status-right` as `#(~/.tmux/git-status.sh '#{pane_current_path}')`
- Refreshes every `status-interval` (1s)
- The script outputs tmux format markup (`#[fg=...]...`) — tmux re-expands `#{...}` directives in `#()` output, so theme color vars (`#{E:@thm_mauve}` etc.) resolve at render time
- When outside a git work tree the script prints nothing, so the entire pill disappears
