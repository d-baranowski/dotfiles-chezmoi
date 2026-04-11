# CLAUDE.md

This is a chezmoi-managed dotfiles repository. Read this before making any changes.

## What is this repo?

This repo is the **source of truth** for the user's dotfiles. It is NOT a normal config directory — files here use chezmoi's naming conventions and are applied to the home directory via `chezmoi apply`.

## Chezmoi naming conventions

Chezmoi uses prefixes to encode file attributes:

- `dot_` → `.` (e.g. `dot_zshrc` → `~/.zshrc`)
- `private_` → file/dir with restricted permissions (0700/0600)
- `executable_` → file with execute permission
- `readonly_` → read-only file
- `.tmpl` suffix → Go template, rendered before applying

Example: `private_dot_config/sketchybar/executable_sketchybarrc` → `~/.config/sketchybar/sketchybarrc` (executable, private parent)

## Repository structure

```
.chezmoidata.yaml          # Secrets (GITIGNORED - never committed)
.chezmoidata.yaml.example  # Template showing which secrets are needed
.chezmoiignore             # Files chezmoi should not manage
.gitignore                 # Standard gitignore

dot_zshrc                  # ~/.zshrc
dot_zshenv                 # ~/.zshenv
dot_zprofile               # ~/.zprofile
dot_aliases                # ~/.aliases
dot_profile                # ~/.profile
dot_tmux.conf              # ~/.tmux.conf
dot_vimrc                  # ~/.vimrc
dot_ideavimrc              # ~/.ideavimrc
dot_gitconfig              # ~/.gitconfig
dot_aerospace.toml         # ~/.aerospace.toml
dot_asdfrc                 # ~/.asdfrc
dot_tool-versions          # ~/.tool-versions
dot_yarnrc                 # ~/.yarnrc
dot_docker/                # ~/.docker/ (config.json, daemon.json)

private_dot_boto           # ~/.boto
private_dot_ssh/config     # ~/.ssh/config
private_dot_config/        # ~/.config/
  alacritty/               #   Terminal emulator + catppuccin themes
  gh/                      #   GitHub CLI config
  git/ignore               #   Global gitignore
  opencode/                #   OpenCode AI tool config
  private_htop/            #   htop config
  private_karabiner/       #   Karabiner key remapping (large JSON)
  sketchybar/              #   Menu bar config + custom plugin scripts

private_dot_mcpproxy/                        # ~/.mcpproxy/
  private_mcp_config.json.tmpl               #   MCPProxy config (TEMPLATE - contains secret placeholders)

private_Library/
  private_LaunchAgents/                      # ~/Library/LaunchAgents/
    com.mcpproxy.serve.plist.tmpl            #   MCPProxy service (TEMPLATE)
  private_Application Support/
    private_Code/User/                       # VS Code settings
      settings.json
      keybindings.json
```

## Templates

Files ending in `.tmpl` are Go templates rendered by chezmoi. They use these variables:

- `{{ .chezmoi.homeDir }}` — user's home directory (replaces hardcoded paths)
- `{{ .mcpproxy_api_key }}` — MCPProxy API key (from `.chezmoidata.yaml`)
- `{{ .postgres_password }}` — PostgreSQL password (from `.chezmoidata.yaml`)

## What is NOT in this repo

- **Secrets** — stored in `.chezmoidata.yaml` (gitignored) and macOS Keychain
- **Tmux plugins** (`~/.tmux/plugins/`) — managed by TPM, install with `prefix + I`
- **Oh-my-zsh plugins** (`~/.oh-my-zsh/custom/plugins/`) — managed by oh-my-zsh
- **SSH keys** — never committed
- **Kubernetes configs** (`~/.kube/`) — contain private keys
- **AWS/GCloud credentials** — contain tokens
- **SOPS/age keys** — encryption private keys

## Rules for AI agents

1. **Never add secrets** to any file in this repo. Use chezmoi template variables instead.
2. **Never edit files in `~/.config/`, `~/.zshrc`, etc. directly** when the user asks to change their config. Edit the chezmoi source file here, then run `chezmoi apply -v`.
3. **To find the source file** for a managed dotfile: `chezmoi source-path ~/.zshrc`
4. **To add a new config**: `chezmoi add ~/path/to/file`
5. **To apply changes**: `chezmoi apply -v`
6. **To preview changes**: `chezmoi diff`
7. **Hardcoded home directory paths** in templates must use `{{ .chezmoi.homeDir }}`, not `/Users/danielbaranowski`.
8. **New secrets** should be added to `.chezmoidata.yaml` (and `.chezmoidata.yaml.example`), then referenced as `{{ .secret_name }}` in `.tmpl` files.
9. **The `.chezmoidata.yaml` file is gitignored.** If you need to add a new secret variable, update both `.chezmoidata.yaml` and `.chezmoidata.yaml.example`.
