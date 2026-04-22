#!/usr/bin/env bash
# Claude Code statusLine renderer.
#
# Reads a JSON object on stdin (model, cost, duration, context window,
# line counts, etc.), prints one line to stdout. Must stay fast — runs
# on every render. Network calls are done in the background only.

set -u

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
PRICE_CACHE="$CACHE_DIR/model_prices.json"
PRICE_URL="https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
PRICE_TTL=$((24 * 3600))
CACHE_TTL_SECS=300  # Anthropic prompt cache TTL — 5 min

mkdir -p "$CACHE_DIR" 2>/dev/null

input="$(cat)"

j() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

# ---- basic fields ----
session_id=$(j '.session_id // "unknown"')
model_id=$(j '.model.id // ""')
model_name=$(j '.model.display_name // .model.id // "?"')
cost=$(j '.total_cost_usd // 0')
exceeds_200k=$(j '.exceeds_200k_tokens // false')

ctx_in=$(j '.context_window.current_usage.input_tokens // 0')
ctx_cache_w=$(j '.context_window.current_usage.cache_creation_input_tokens // 0')
ctx_cache_r=$(j '.context_window.current_usage.cache_read_input_tokens // 0')
ctx_out=$(j '.context_window.current_usage.output_tokens // 0')
ctx_size=$(j '.context_window.context_window_size // 200000')

# ---- price table (networked + cached) ----
refresh_prices_bg() {
  # Avoid concurrent downloads via mkdir (atomic). Detach with nohup so the
  # fetch survives after the statusLine command exits — otherwise macOS would
  # SIGTERM the child when Claude Code reaps the process group.
  local lockdir="$CACHE_DIR/.refresh.lock.d"
  mkdir "$lockdir" 2>/dev/null || return 0
  nohup bash -c '
    trap "rmdir \"$0\" 2>/dev/null" EXIT
    tmp="$1.tmp.$$"
    if curl -fsSL --max-time 10 "$2" -o "$tmp" 2>/dev/null; then
      mv "$tmp" "$1"
    else
      rm -f "$tmp"
    fi
  ' "$lockdir" "$PRICE_CACHE" "$PRICE_URL" </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

price_cache_age() {
  if [[ -f "$PRICE_CACHE" ]]; then
    now=$(date +%s)
    mtime=$(stat -f %m "$PRICE_CACHE" 2>/dev/null || stat -c %Y "$PRICE_CACHE" 2>/dev/null || echo 0)
    echo $(( now - mtime ))
  else
    echo 999999999
  fi
}

# Strip suffixes like "[1m]" and trailing "-YYYYMMDD"
normalize_model() {
  local m="$1"
  m="${m%%\[*}"              # drop [1m], [anything]
  m="${m%-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]}"  # drop -YYYYMMDD
  printf '%s' "$m"
}

lookup_price_from_cache() {
  # Outputs "$IN $OUT" (dollars per Mtok) or empty.
  local m="$1"
  [[ -f "$PRICE_CACHE" ]] || return
  local row
  row=$(jq -r --arg m "$m" '
    (.[$m] // empty) as $r
    | if $r == null then empty
      else "\(($r.input_cost_per_token // 0) * 1000000) \(($r.output_cost_per_token // 0) * 1000000)"
      end
  ' "$PRICE_CACHE" 2>/dev/null)
  [[ -n "$row" && "$row" != "0 0" ]] && printf '%s' "$row"
}

# Hardcoded fallback for cold cache / offline. $in $out per Mtok.
fallback_price() {
  local m="$1"
  case "$m" in
    claude-opus-4*)    echo "15 75" ;;
    claude-sonnet-4*)  echo "3 15" ;;
    claude-haiku-4*)   echo "1 5" ;;
    claude-3-5-sonnet*|claude-3-7-sonnet*) echo "3 15" ;;
    claude-3-5-haiku*) echo "0.80 4" ;;
    claude-3-opus*)    echo "15 75" ;;
    *) echo "" ;;
  esac
}

# Schedule background refresh if stale/missing.
age=$(price_cache_age)
if (( age > PRICE_TTL )); then
  refresh_prices_bg
fi

norm=$(normalize_model "$model_id")
price_pair=""
for candidate in "$model_id" "$norm"; do
  [[ -z "$candidate" ]] && continue
  price_pair=$(lookup_price_from_cache "$candidate")
  [[ -n "$price_pair" ]] && break
done
if [[ -z "$price_pair" ]]; then
  price_pair=$(fallback_price "$norm")
fi

if [[ -n "$price_pair" ]]; then
  pin=${price_pair% *}
  pout=${price_pair#* }
  # Trim trailing zeros for neat display (e.g. "15" not "15.0000000")
  fmt_price() {
    awk -v n="$1" 'BEGIN { if (n == int(n)) printf "%d", n; else printf "%.2f", n }'
  }
  rate_card="\$$(fmt_price "$pin")/\$$(fmt_price "$pout")"
else
  rate_card="\$?/\$?"
fi

# ---- per-session state: cache freshness + deltas ----
state_file="/tmp/claude-statusline-${session_id}.json"
now=$(date +%s)
total_tokens=$(( ctx_in + ctx_cache_w + ctx_cache_r + ctx_out ))

prev_cost=0; prev_tokens=0; prev_cache_w=0; cache_ts=$now
if [[ -f "$state_file" ]]; then
  prev_cost=$(jq -r '.cost // 0' "$state_file" 2>/dev/null)
  prev_tokens=$(jq -r '.tokens // 0' "$state_file" 2>/dev/null)
  prev_cache_w=$(jq -r '.cache_w // 0' "$state_file" 2>/dev/null)
  cache_ts=$(jq -r '.cache_ts // 0' "$state_file" 2>/dev/null)
fi

# Cache was (re)written this turn if cache_creation_input_tokens increased.
if awk -v a="$ctx_cache_w" -v b="$prev_cache_w" 'BEGIN { exit !(a+0 > b+0) }'; then
  cache_ts=$now
fi

# Persist state for next render.
jq -n \
  --arg cost "$cost" \
  --arg tokens "$total_tokens" \
  --arg cache_w "$ctx_cache_w" \
  --arg cache_ts "$cache_ts" \
  '{cost: ($cost|tonumber), tokens: ($tokens|tonumber), cache_w: ($cache_w|tonumber), cache_ts: ($cache_ts|tonumber)}' \
  > "$state_file" 2>/dev/null

# ---- formatting helpers ----
fmt_cost() { awk -v c="$1" 'BEGIN { printf "$%.2f", c }'; }

fmt_cost_delta() {
  awk -v d="$1" 'BEGIN {
    if (d <= 0) { printf ""; exit }
    if (d < 0.01) printf "+$%.4f", d
    else printf "+$%.2f", d
  }'
}

fmt_tokens() {
  awk -v t="$1" 'BEGIN {
    if (t <= 0) { printf ""; exit }
    if (t >= 1000000) printf "+%.1fM tok", t/1000000
    else if (t >= 1000) printf "+%dk tok", int(t/1000)
    else printf "+%d tok", t
  }'
}

fmt_cache_remaining() {
  local elapsed=$(( now - cache_ts ))
  local remaining=$(( CACHE_TTL_SECS - elapsed ))
  if (( remaining <= 0 )); then
    printf 'cache EXPIRED'
  else
    printf 'cache %dm:%02ds' $(( remaining / 60 )) $(( remaining % 60 ))
  fi
}

# ---- context bar ----
current_ctx=$(( ctx_in + ctx_cache_w + ctx_cache_r ))
if (( ctx_size > 0 )); then
  pct=$(( current_ctx * 100 / ctx_size ))
else
  pct=0
fi
(( pct > 100 )) && pct=100
filled=$(( pct / 5 ))
empty=$(( 20 - filled ))
bar=""
(( filled > 0 )) && bar+=$(printf '█%.0s' $(seq 1 $filled))
(( empty > 0 )) && bar+=$(printf '░%.0s' $(seq 1 $empty))

# ---- deltas ----
cost_delta=$(awk -v a="$cost" -v b="$prev_cost" 'BEGIN { printf "%.6f", a - b }')
token_delta=$(( total_tokens - prev_tokens ))
delta_cost_str=$(fmt_cost_delta "$cost_delta")
delta_tok_str=$(fmt_tokens "$token_delta")
delta_parts=""
if [[ -n "$delta_cost_str" || -n "$delta_tok_str" ]]; then
  if [[ -n "$delta_cost_str" && -n "$delta_tok_str" ]]; then
    delta_parts=" ($delta_cost_str, $delta_tok_str)"
  else
    delta_parts=" (${delta_cost_str}${delta_tok_str})"
  fi
fi

# ---- assemble ----
sep=" │ "
line="${model_name} ${rate_card}"
line+="${sep}$(fmt_cost "$cost")${delta_parts}"
line+="${sep}${pct}% [${bar}]"
line+="${sep}$(fmt_cache_remaining)"
if [[ "$exceeds_200k" == "true" ]]; then
  line+="${sep}!200k"
fi
# Timestamp of this render — i.e. when the last turn completed.
line+="${sep}$(date +'%H:%M')"

printf '%s' "$line"
