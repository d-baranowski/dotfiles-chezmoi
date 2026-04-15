#!/bin/sh
# Claude Code Stop hook: refresh the session recap sidecar in the background.
#
# Fires at the end of every assistant turn. Hands the current session's jsonl
# path to ~/.config/television/claude-recap-gen.py and detaches so Claude's
# shutdown is never gated on the Haiku call. The generator itself short-
# circuits when the jsonl hasn't grown meaningfully since the last recap, so
# firing on every Stop is cheap.
#
# RECURSION GUARD: the generator spawns `claude -p` to do the summarisation,
# which itself is a Claude Code session that fires Stop hooks. Without a
# guard, Stop would fire on the ephemeral recap session, spawning another
# recap-gen, spawning another `claude -p`, ad infinitum — a fork-bomb that
# burns real API tokens. Two defences below:
#
#   1. CLAUDE_RECAP_GEN env var: the generator sets this when invoking
#      `claude -p`; it's inherited by the spawned claude process and any
#      hooks it fires. We check it first and bail out.
#
#   2. Transcript content check: peek at the first user message; if it
#      looks like one of our recap prompts, bail. Covers any case where
#      the env var doesn't propagate (plugin runners, sandboxes, etc.).
#
# Why do this at all: the TV channel preview is the other consumer, but it
# only regenerates when you *open* a stale session — which adds first-look
# latency. This hook keeps the cache warm while you work.

set -eu

# Defence 1: env-var guard.
[ -z "${CLAUDE_RECAP_GEN:-}" ] || exit 0

input="$(cat || true)"
transcript_path="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
[ -n "$transcript_path" ] || exit 0
[ -f "$transcript_path" ] || exit 0

# Defence 2: if this session's first user message looks like one of our
# recap prompts, it's a summarisation session — don't recurse.
first_user="$(
  awk -F '"' '/"type":"user"/ {print; exit}' "$transcript_path" 2>/dev/null \
    | head -c 400
)"
case "$first_user" in
  *"Summarize this Claude Code session in ONE"*) exit 0 ;;
  *"You previously summarised a Claude Code session"*) exit 0 ;;
esac

gen="$HOME/.config/television/claude-recap-gen.py"
[ -x "$gen" ] || exit 0

# Detach fully so Claude doesn't wait on us. Output swallowed.
nohup "$gen" "$transcript_path" >/dev/null 2>&1 &
