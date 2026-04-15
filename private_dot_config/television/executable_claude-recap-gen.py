#!/usr/bin/env python3
"""Generate or refresh a one-line recap for a Claude session jsonl.

Spawned in the background by claude-session-preview.py. Uses `claude -p`
(headless mode) so usage counts against the Max plan's Claude Code quota
rather than being billed via API credits.

Output is a JSON sidecar at <jsonl>.recap:

    {
      "recap": "Added git status pill to tmux bar",
      "jsonl_size": 123456,
      "jsonl_mtime": 1713456789.0,
      "turn_count": 12,
      "generated_at": 1713456790.0
    }

If a prior recap exists, it's fed to the model as seed context alongside
only the *new* turns since the last recap was generated — cheaper than
re-summarising the whole transcript, and yields coherent progressive
summaries. A <jsonl>.recap.lock sentinel prevents duplicate concurrent
generations; it's removed on exit.
"""
import json
import os
import subprocess
import sys
import time

TURN_LIMIT = 30           # how many user/assistant turns to feed on a cold recap
PER_TURN_CHARS = 500      # truncate each turn to keep the prompt bounded
MAX_TRANSCRIPT = 8000     # hard cap on the transcript block
MAX_RECAP_CHARS = 200
CLAUDE_TIMEOUT = 90       # seconds
# When a prior recap exists, skip the LLM call unless the jsonl has grown
# by at least this much. Mirrors STALENESS_BYTES in claude-session-preview.py.
# Lets the Stop hook fire eagerly without burning a Haiku call every turn.
MIN_GROWTH_BYTES = 2000

INITIAL_PROMPT = (
    "Summarize this Claude Code session in ONE short sentence "
    "(max 80 characters). Focus on the task or problem the user asked about. "
    "Reply with ONLY the sentence — no preamble, no quotes, no trailing period "
    "if it can be avoided.\n\n---\n"
)

UPDATE_PROMPT_TEMPLATE = (
    "You previously summarised a Claude Code session as:\n"
    "  {prior}\n\n"
    "Since then, these additional turns have happened:\n"
    "---\n{new_turns}\n---\n\n"
    "Produce an UPDATED one-sentence summary (max 80 chars) that reflects "
    "the session as a whole including the new turns. If the new turns don't "
    "meaningfully change the summary, return the previous one unchanged. "
    "Reply with ONLY the sentence — no preamble, no quotes."
)


def iter_turns(jsonl_path):
    """Yield (index, role, text) for each user/assistant turn in order."""
    idx = 0
    with open(jsonl_path) as f:
        for line in f:
            try:
                d = json.loads(line)
            except Exception:
                continue
            t = d.get("type")
            if t not in ("user", "assistant"):
                continue
            content = d.get("message", {}).get("content", "")
            if isinstance(content, list):
                bits = [
                    c.get("text", "")
                    for c in content
                    if isinstance(c, dict) and c.get("type") == "text"
                ]
                content = "\n".join(bits)
            if not isinstance(content, str):
                continue
            content = content.strip()
            if not content:
                continue
            yield idx, t, content
            idx += 1


def render_turns(turns):
    parts = []
    for _idx, role, text in turns:
        label = "USER" if role == "user" else "CLAUDE"
        parts.append("%s: %s" % (label, text[:PER_TURN_CHARS]))
    return "\n\n".join(parts)[:MAX_TRANSCRIPT]


def read_prior(recap_path):
    """Return the prior recap dict if the sidecar is valid JSON, else None."""
    try:
        with open(recap_path) as f:
            data = json.load(f)
        if isinstance(data, dict) and data.get("recap"):
            return data
    except Exception:
        pass
    return None


def main():
    if len(sys.argv) != 2:
        sys.exit(1)
    jsonl = sys.argv[1]
    recap_path = jsonl + ".recap"
    lock_path = recap_path + ".lock"

    # Atomic lock so concurrent previews don't race.
    try:
        fd = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        os.close(fd)
    except FileExistsError:
        return

    try:
        st = os.stat(jsonl)
        prior = read_prior(recap_path)
        all_turns = list(iter_turns(jsonl))
        turn_count = len(all_turns)

        if not all_turns:
            _write_recap(recap_path, "— no content to summarise —", st, turn_count)
            return

        if prior:
            prior_turn_count = int(prior.get("turn_count") or 0)
            prior_size = int(prior.get("jsonl_size") or 0)
            new_turns = all_turns[prior_turn_count:]
            if not new_turns:
                # Nothing new — just refresh the metadata so we stop re-firing.
                _write_recap(recap_path, prior["recap"], st, turn_count)
                return
            if st.st_size - prior_size < MIN_GROWTH_BYTES:
                # Not enough new material to justify a Haiku call. Refresh
                # metadata (keeps turn_count current) and keep the recap.
                _write_recap(recap_path, prior["recap"], st, turn_count)
                return
            # Cap new-turn transcript the same way we cap cold generation.
            rendered = render_turns(new_turns[-TURN_LIMIT:])
            prompt = UPDATE_PROMPT_TEMPLATE.format(
                prior=prior["recap"], new_turns=rendered
            )
        else:
            rendered = render_turns(all_turns[:TURN_LIMIT])
            prompt = INITIAL_PROMPT + rendered

        result = subprocess.run(
            ["claude", "-p", prompt],
            capture_output=True,
            text=True,
            timeout=CLAUDE_TIMEOUT,
        )
        out = (result.stdout or "").strip()
        recap = ""
        for line in out.splitlines():
            line = line.strip()
            if line:
                recap = line
                break
        if recap and len(recap) >= 2 and recap[0] == recap[-1] and recap[0] in ("'", '"'):
            recap = recap[1:-1].strip()
        if not recap:
            recap = prior["recap"] if prior else "— recap unavailable —"
        recap = recap[:MAX_RECAP_CHARS]

        _write_recap(recap_path, recap, st, turn_count)
    except Exception as e:
        # Preserve any prior recap; just don't blow up. If we have no prior,
        # cache a failure marker so we don't retry on every preview keystroke.
        if not read_prior(recap_path):
            try:
                st = os.stat(jsonl)
                _write_recap(
                    recap_path,
                    "— recap failed: %s —" % str(e)[:80],
                    st,
                    0,
                )
            except Exception:
                pass
    finally:
        try:
            os.unlink(lock_path)
        except FileNotFoundError:
            pass


def _write_recap(path, recap, st, turn_count):
    payload = {
        "recap": recap.rstrip(),
        "jsonl_size": st.st_size,
        "jsonl_mtime": st.st_mtime,
        "turn_count": turn_count,
        "generated_at": time.time(),
    }
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(payload, f)
        f.write("\n")
    os.rename(tmp, path)


if __name__ == "__main__":
    main()
