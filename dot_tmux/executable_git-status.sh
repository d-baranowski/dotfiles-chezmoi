#!/usr/bin/env bash
# Renders a catppuccin-styled git pill for the tmux status bar.
# Outputs nothing when the given path is not inside a git work tree.
#
# Segments (only shown when non-zero):
#    branch          current branch (or short SHA in detached HEAD)
#   Nf               total changed files (staged + unstaged + untracked)
#   ●+ins/-del       staged line changes
#   ○+ins/-del       unstaged line changes
#   ⇡ahead⇣behind    commits ahead/behind upstream
#   ⊘                no upstream configured

path="${1:-$PWD}"
cd "$path" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

branch=$(git symbolic-ref --short HEAD 2>/dev/null) \
  || branch=$(git rev-parse --short HEAD 2>/dev/null)
[ -z "$branch" ] && exit 0

files=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

parse_shortstat() {
  local stat ins del
  stat=$(git diff $1 --shortstat 2>/dev/null)
  ins=$(printf '%s' "$stat" | grep -oE '[0-9]+ insertion' | grep -oE '^[0-9]+')
  del=$(printf '%s' "$stat" | grep -oE '[0-9]+ deletion'  | grep -oE '^[0-9]+')
  echo "${ins:-0} ${del:-0}"
}

read u_ins u_del <<<"$(parse_shortstat '')"
read s_ins s_del <<<"$(parse_shortstat '--cached')"

ahead=0
behind=0
has_upstream=0
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
  has_upstream=1
  ahead=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
  behind=$(git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
fi

content=" $branch"
[ "$files" -gt 0 ] && content="$content  ${files}f"
if [ "$s_ins" -gt 0 ] || [ "$s_del" -gt 0 ]; then
  content="$content  ●+${s_ins}/-${s_del}"
fi
if [ "$u_ins" -gt 0 ] || [ "$u_del" -gt 0 ]; then
  content="$content  ○+${u_ins}/-${u_del}"
fi
if [ "$has_upstream" -eq 1 ]; then
  if [ "$ahead" -gt 0 ] || [ "$behind" -gt 0 ]; then
    content="$content  ⇡${ahead}⇣${behind}"
  fi
else
  content="$content  ⊘"
fi

# Output as a catppuccin-style pill. tmux re-expands #{...} in #() output,
# so the theme color vars resolve at render time.
printf '#[fg=#{E:@thm_mauve},bg=default]#{E:@catppuccin_status_left_separator}#[fg=#{E:@thm_crust},bg=#{E:@thm_mauve}]  #[fg=#{E:@thm_fg},bg=#{E:@thm_surface_0}]%s #[fg=#{E:@thm_surface_0},bg=default]#{E:@catppuccin_status_right_separator} ' "$content"
