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

When running inside tmux, keep your pane title saying what this session holds, so the user can
find the right pane among many. Run `~/.claude/bin/pane-title "<worked on> - <working on now>"`
at the start of each task and whenever either half changes:

- **Worked on**: the tasks already in your context, a few plain English words each, e.g.
  `bank transfer docs, therapy tab reset`. It tells the user what you can be asked about.
- **Working on now**: the current task in a few plain English words, or `idle`.

Plain words only: no ticket, PR or card numbers, which tell the user nothing at a glance.
Example: `~/.claude/bin/pane-title "bank transfer docs, flaky e2e tests - watching CI"`. At the
very start, before anything is done, use only the second half. It does nothing outside tmux.

# Dotfiles

All dotfiles are managed by chezmoi. Never edit target files directly — edit
the chezmoi source and run `chezmoi apply -v`. See the project CLAUDE.md in
the dotfiles repo for full conventions.
