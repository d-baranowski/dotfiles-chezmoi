#!/bin/sh
# Claude Code Stop hook: refresh the session recap sidecar in the background.
#
# Fires at the end of every assistant turn. Hands the current session's jsonl
# path to ~/.config/television/claude-recap-gen.py and detaches so Claude's
# shutdown is never gated on the Haiku call. The generator itself short-
# circuits when the jsonl hasn't grown meaningfully since the last recap, so
# firing on every Stop is cheap.
#
# Why do this at all: the TV channel preview is the other consumer, but it
# only regenerates when you *open* a stale session — which adds first-look
# latency. This hook keeps the cache warm while you work.

set -eu

input="$(cat || true)"
transcript_path="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
[ -n "$transcript_path" ] || exit 0
[ -f "$transcript_path" ] || exit 0

gen="$HOME/.config/television/claude-recap-gen.py"
[ -x "$gen" ] || exit 0

# Detach fully so Claude doesn't wait on us. Output swallowed.
nohup "$gen" "$transcript_path" >/dev/null 2>&1 &
