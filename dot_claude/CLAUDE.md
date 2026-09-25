# Global Preferences

- Always use pnpm — never npm or yarn
- Preferred editor: nvim (neovim)
- Use async/await over callbacks in JS/TS

# Tech Stack

- Languages: Go, TypeScript/Node.js, Java
- Package management: pnpm, asdf for runtimes
- Infrastructure: Docker Compose, Terraform, Kubernetes
- IDEs: Neovim, VS Code, GoLand
- macOS: Aerospace (tiling WM), Sketchybar, LeaderKeyApp, Hammerspoon, Karabiner
- Dotfiles: chezmoi (source of truth is ~/Workspace/dotfiles-chezmoi)
- Git: conventional commits, branch from main

# tmux pane title

When running inside tmux, keep your pane title saying what you are working on, so the user can
find the right pane among many. At the start of each task, and whenever the task changes, run
`~/.claude/bin/pane-title "<ticket or repo>: <task in 3-6 words>"`, for example
`~/.claude/bin/pane-title "UTR-000815: fix therapy tab remount"`. It does nothing outside tmux.

# Dotfiles

All dotfiles are managed by chezmoi. Never edit target files directly — edit
the chezmoi source and run `chezmoi apply -v`. See the project CLAUDE.md in
the dotfiles repo for full conventions.
