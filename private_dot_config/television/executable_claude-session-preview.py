#!/usr/bin/env python3
"""Preview a Claude Code session by session ID.

Shows a statusline-style recap (model, rate card, cost, tokens, duration,
turns) followed by the first ~20 user/assistant turns. Cost is estimated
from per-turn token usage against the same hardcoded price table used by
the statusline (dot_claude/statusline/executable_statusline.sh) — keep
the two in sync.
"""
import datetime
import glob
import json
import os
import re
import subprocess
import sys

if len(sys.argv) < 2:
    print("Usage: claude-session-preview.py <session-id>")
    sys.exit(1)

sid = sys.argv[1]
base = os.path.expanduser("~/.claude/projects")

# $in/$out per Mtok. Mirrors fallback_price() in statusline.sh.
PRICES = [
    (re.compile(r"^claude-opus-4"), (15.0, 75.0)),
    (re.compile(r"^claude-sonnet-4"), (3.0, 15.0)),
    (re.compile(r"^claude-haiku-4"), (1.0, 5.0)),
    (re.compile(r"^claude-3-5-sonnet"), (3.0, 15.0)),
    (re.compile(r"^claude-3-7-sonnet"), (3.0, 15.0)),
    (re.compile(r"^claude-3-5-haiku"), (0.80, 4.0)),
    (re.compile(r"^claude-3-opus"), (15.0, 75.0)),
]


def normalize_model(m):
    if not m:
        return ""
    m = re.sub(r"\[[^\]]*\]$", "", m)            # drop [1m]
    m = re.sub(r"-\d{8}$", "", m)                # drop -YYYYMMDD
    return m


def price_for(model):
    n = normalize_model(model)
    for pat, p in PRICES:
        if pat.match(n):
            return p
    return None


def fmt_price(n):
    return ("%d" % n) if n == int(n) else ("%.2f" % n)


def fmt_tokens(n):
    if n <= 0:
        return "0"
    if n < 1000:
        return str(n)
    if n < 1_000_000:
        return "%dk" % round(n / 1000)
    return "%.1fM" % (n / 1_000_000)


def fmt_duration(secs):
    s = int(secs)
    if s >= 3600:
        return "%dh %dm" % (s // 3600, (s % 3600) // 60)
    if s >= 60:
        return "%dm" % (s // 60)
    return "%ds" % s


def parse_ts(s):
    if not s:
        return None
    try:
        return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


# Regenerate when the jsonl has grown by more than this since the recap was
# made. About one full turn's worth — small enough to stay fresh, large enough
# to avoid firing on trivial appends like permission-mode events.
STALENESS_BYTES = 2000


def _spawn_gen(jsonl):
    """Fire the background recap generator, detached. No-op if its lock file
    exists (another preview already kicked one off)."""
    if os.path.exists(jsonl + ".recap.lock"):
        return
    gen = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "claude-recap-gen.py"
    )
    if not os.path.exists(gen):
        return
    try:
        subprocess.Popen(
            [sys.executable, gen, jsonl],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            stdin=subprocess.DEVNULL,
            start_new_session=True,
        )
    except Exception:
        pass


def load_or_spawn_recap(jsonl):
    """Return the recap string to display.

    - No sidecar: spawn generator, show "generating…".
    - JSON sidecar, fresh (jsonl hasn't grown much): show recap.
    - JSON sidecar, stale: spawn generator, show "<prior> (updating…)" so the
      user always sees something and knows a refresh is in flight. The
      generator will feed the prior recap to Haiku as seed context.
    - Plain-text sidecar (legacy, pre-JSON): treat as stale with unknown prior.
    """
    recap_path = jsonl + ".recap"
    if not os.path.exists(recap_path):
        _spawn_gen(jsonl)
        return "generating… (reopen session to refresh)"

    # Try JSON first (current format).
    try:
        with open(recap_path) as f:
            data = json.load(f)
        if isinstance(data, dict) and data.get("recap"):
            recap = data["recap"]
            prior_size = int(data.get("jsonl_size") or 0)
            try:
                current_size = os.path.getsize(jsonl)
            except OSError:
                current_size = prior_size
            if current_size - prior_size >= STALENESS_BYTES:
                _spawn_gen(jsonl)
                return recap + " (updating…)"
            return recap
    except (json.JSONDecodeError, ValueError):
        pass
    except Exception:
        pass

    # Legacy plain-text sidecar — read, show, and trigger a one-time upgrade
    # to the JSON format. We delete it so the generator treats it as cold
    # rather than trying to parse it as prior JSON.
    try:
        with open(recap_path) as f:
            legacy = f.read().strip()
    except Exception:
        legacy = ""
    try:
        os.unlink(recap_path)
    except OSError:
        pass
    _spawn_gen(jsonl)
    return (legacy or "generating…") + " (updating…)"


for jsonl in glob.glob(os.path.join(base, "**", sid + ".jsonl"), recursive=True):
    project = os.path.basename(os.path.dirname(jsonl))

    # ---- pass 1: aggregate recap stats ----
    models = {}                # model_id -> count of assistant turns
    cost = 0.0
    last_usage = None
    last_model = None
    first_ts = None
    last_ts = None
    user_turns = 0
    assistant_turns = 0
    try:
        with open(jsonl) as f:
            for line in f:
                try:
                    d = json.loads(line.strip())
                except Exception:
                    continue
                ts = parse_ts(d.get("timestamp"))
                if ts is not None:
                    if first_ts is None:
                        first_ts = ts
                    last_ts = ts
                t = d.get("type")
                if t == "user":
                    user_turns += 1
                elif t == "assistant":
                    assistant_turns += 1
                    m = d.get("message", {})
                    mdl = m.get("model") or ""
                    if mdl:
                        models[mdl] = models.get(mdl, 0) + 1
                        last_model = mdl
                    u = m.get("usage") or {}
                    if u:
                        last_usage = u
                        p = price_for(mdl)
                        if p:
                            pin, pout = p
                            # Cache reads ~= 0.1x input; cache writes ~= 1.25x input.
                            in_t = u.get("input_tokens", 0) or 0
                            cw = u.get("cache_creation_input_tokens", 0) or 0
                            cr = u.get("cache_read_input_tokens", 0) or 0
                            out_t = u.get("output_tokens", 0) or 0
                            cost += (in_t * pin + cw * pin * 1.25 + cr * pin * 0.1 + out_t * pout) / 1_000_000
    except Exception as e:
        print("Error reading session: " + str(e))
        break

    # ---- assemble recap ----
    print("Project: " + project)
    print("Session: " + sid)
    print("Recap:   " + load_or_spawn_recap(jsonl))

    if last_model:
        p = price_for(last_model)
        rate = ("$%s/$%s" % (fmt_price(p[0]), fmt_price(p[1]))) if p else "$?/$?"
        model_label = normalize_model(last_model)
        if len(models) > 1:
            model_label += " (+%d others)" % (len(models) - 1)
        print("Model:   %s  %s" % (model_label, rate))

    print("Cost:    $%.2f  (estimated)" % cost)

    if last_usage:
        ctx = (
            (last_usage.get("input_tokens", 0) or 0)
            + (last_usage.get("cache_creation_input_tokens", 0) or 0)
            + (last_usage.get("cache_read_input_tokens", 0) or 0)
        )
        out_t = last_usage.get("output_tokens", 0) or 0
        print("Context: %s in · %s out" % (fmt_tokens(ctx), fmt_tokens(out_t)))

    if first_ts and last_ts and last_ts > first_ts:
        print("Wall:    %s" % fmt_duration(last_ts - first_ts))

    print("Turns:   %d user · %d assistant" % (user_turns, assistant_turns))
    print("-" * 60)

    # ---- pass 2: replay first ~20 turns ----
    try:
        with open(jsonl) as f:
            turn = 0
            for line in f:
                d = json.loads(line.strip())
                role = d.get("type", "")
                if role not in ("user", "assistant"):
                    continue
                msg = d.get("message", {}).get("content", "")
                if isinstance(msg, list):
                    parts = []
                    for c in msg:
                        if isinstance(c, dict) and c.get("type") == "text":
                            parts.append(c["text"])
                    msg = " ".join(parts)
                if not msg:
                    continue
                msg = re.sub(r"<[^>]+>", "", msg).strip()
                if not msg:
                    continue
                prefix = ">>> USER" if role == "user" else "<<< CLAUDE"
                print("\n" + prefix + ":")
                print(msg[:500])
                turn += 1
                if turn > 20:
                    print("\n... (truncated)")
                    break
    except Exception as e:
        print("Error: " + str(e))
    break
