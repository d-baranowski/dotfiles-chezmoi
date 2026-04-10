# Dotfiles

My dotfiles, managed with [chezmoi](https://www.chezmoi.io/).

## How it works

Chezmoi keeps a **source copy** of your dotfiles in this repo. When you run `chezmoi apply`, it copies them to the right places in your home directory. You never edit your actual config files directly — you edit the source copy here, then apply.

```
~/Workspace/dotfiles-chezmoi/       →  chezmoi apply  →  ~/.zshrc, ~/.tmux.conf, etc.
       (source of truth)                                    (your actual configs)
```

## Daily workflow

### Editing a config

```bash
# Option 1: edit via chezmoi (opens the source copy in $EDITOR)
chezmoi edit ~/.zshrc

# Option 2: edit directly in the repo
vim ~/Workspace/dotfiles-chezmoi/dot_zshrc

# Then apply changes to your home directory
chezmoi apply -v
```

### After editing a config directly (e.g. via an app's settings UI)

If you changed a file directly (VS Code settings, Karabiner, etc.), pull the changes back into chezmoi:

```bash
chezmoi add ~/.config/karabiner/karabiner.json
```

### See what would change before applying

```bash
chezmoi diff
```

### Dry run (no changes made)

```bash
chezmoi apply -v -n
```

## What's managed

| Config | Files |
|--------|-------|
| Zsh | `.zshrc`, `.zshenv`, `.zprofile`, `.aliases`, `.profile` |
| Tmux | `.tmux.conf` |
| Vim | `.vimrc`, `.ideavimrc` |
| Git | `.gitconfig`, `.config/git/ignore` |
| VS Code | `settings.json`, `keybindings.json` |
| Aerospace | `.aerospace.toml` |
| Sketchybar | `sketchybarrc`, `colors.sh`, all plugins |
| Karabiner | `karabiner.json` |
| Alacritty | `alacritty.toml` + catppuccin themes |
| GitHub CLI | `config.yml`, `hosts.yml` |
| SSH | `config` (hosts only, no keys) |
| Docker | `config.json`, `daemon.json` |
| ASDF | `.asdfrc`, `.tool-versions` |
| MCPProxy | `mcp_config.json` (templated), `loki-shipper.sh` |
| LaunchAgents | mcpproxy service plists |
| OpenCode | `opencode.json` |

### Not managed (installed by plugin managers)

- **Tmux plugins** (`~/.tmux/plugins/`) — installed by TPM, run `prefix + I`
- **Oh-my-zsh plugins** (`~/.oh-my-zsh/custom/plugins/`) — installed by oh-my-zsh

## Setting up a new machine

```bash
# 1. Install chezmoi
brew install chezmoi

# 2. Clone and init
chezmoi init https://github.com/d-baranowski/dotfiles-chezmoi.git

# 3. Create the secrets file from the example
cp $(chezmoi source-path)/.chezmoidata.yaml.example $(chezmoi source-path)/.chezmoidata.yaml
# Edit .chezmoidata.yaml and fill in your secrets

# 4. Preview changes
chezmoi diff

# 5. Apply
chezmoi apply -v

# 6. Install tmux plugins
# Open tmux, then press prefix + I

# 7. Install oh-my-zsh plugins
# Handled automatically by .zshrc on next shell start

# 8. Set up mcpproxy secrets in OS keyring
mcpproxy secrets set github_pat
mcpproxy secrets set trello_api_key
mcpproxy secrets set trello_token
```

## Secrets

Secrets are stored in `.chezmoidata.yaml` (gitignored, never committed). Template files (`.tmpl`) reference them as `{{ .variable_name }}`.

| Secret | Used in |
|--------|---------|
| `mcpproxy_api_key` | `~/.mcpproxy/mcp_config.json` |
| `postgres_password` | `~/.mcpproxy/mcp_config.json` |

MCPProxy also stores secrets in the **macOS Keychain** via `mcpproxy secrets set`. These are referenced in the config as `${keyring:name}` and are separate from chezmoi.

## Useful commands

```bash
chezmoi managed                # List all managed files
chezmoi unmanaged              # List files in ~ not managed by chezmoi
chezmoi add ~/path/to/file     # Start managing a new file
chezmoi forget ~/path/to/file  # Stop managing a file
chezmoi edit ~/.zshrc           # Edit a managed file
chezmoi diff                   # Preview pending changes
chezmoi apply -v               # Apply changes
chezmoi update                 # Pull from git + apply
chezmoi cd                     # cd into the source directory
```
