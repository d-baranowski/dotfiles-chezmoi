#!/usr/bin/env python3
"""Render a slackdump SQLite archive into Obsidian markdown.

Usage:
  slackdump-to-md.py <archive.sqlite> <output-dir> [<attachments-prefix>]
                     [--types=im,mpim,public_channel,private_channel]
                     [--only=<channel_id>[,<id>...]]

One .md per channel per day, grouped under a per-channel folder.
Day filenames are DD-MM-YYYY. Thread replies stay with their parent's
date to keep threads visually intact.

`attachments-prefix` is the path (relative to the .md) where attachments
resolve — typically via a symlink from the vault to the archive's
__uploads/ dir. `--types` restricts which channel kinds are emitted
(useful when an archive leaked channels across a -refresh). `--only`
emits just the listed channel IDs.

Regenerates idempotently: per-day files are only re-written when their
content actually changes (avoids Obsidian watcher / sync churn).
"""

from __future__ import annotations

import json
import re
import sqlite3
import sys
import urllib.parse
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


def slug(s: str) -> str:
    """Filesystem-safe name for vault files."""
    s = re.sub(r"[^\w\s.-]", "", s, flags=re.UNICODE).strip()
    s = re.sub(r"\s+", "-", s)
    return s or "untitled"


def load_users(conn: sqlite3.Connection) -> dict[str, str]:
    """user_id → display name, preferring real_name over username."""
    users: dict[str, str] = {}
    for uid, username, data in conn.execute(
        "SELECT ID, USERNAME, DATA FROM S_USER"
    ):
        try:
            d = json.loads(data)
            real = d.get("real_name") or d.get("profile", {}).get("real_name")
            display = d.get("profile", {}).get("display_name")
            users[uid] = real or display or username or uid
        except (json.JSONDecodeError, TypeError):
            users[uid] = username or uid
    return users


def load_channels(conn: sqlite3.Connection) -> dict[str, dict]:
    """Latest CHANNEL row per ID (slackdump may record multiple versions)."""
    channels: dict[str, dict] = {}
    for cid, name, data in conn.execute(
        "SELECT c.ID, c.NAME, c.DATA "
        "FROM CHANNEL c "
        "JOIN (SELECT ID, MAX(CHUNK_ID) mx FROM CHANNEL GROUP BY ID) m "
        "  ON c.ID = m.ID AND c.CHUNK_ID = m.mx"
    ):
        try:
            d = json.loads(data)
        except (json.JSONDecodeError, TypeError):
            d = {}
        channels[cid] = {"name": name, "data": d}
    return channels


def channel_title(cid: str, meta: dict, users: dict[str, str]) -> str:
    """Human-friendly title for a channel/DM/MPIM."""
    d = meta["data"]
    if d.get("is_im"):
        other = d.get("user", "")
        return users.get(other, other or cid)
    if d.get("is_mpim"):
        # MPIM names look like: mpdm-alice--bob--carol-1
        raw = meta["name"] or d.get("name", "")
        parts = re.sub(r"^mpdm-", "", raw)
        parts = re.sub(r"-\d+$", "", parts)
        return ", ".join(parts.split("--")) or cid
    return meta["name"] or d.get("name") or cid


RE_USER_MENTION = re.compile(r"<@([UW][A-Z0-9]+)(?:\|[^>]+)?>")
RE_CHAN_MENTION = re.compile(r"<#([CG][A-Z0-9]+)(?:\|([^>]+))?>")
RE_LINK = re.compile(r"<(https?://[^|>]+)(?:\|([^>]+))?>")


def render_text(text: str, users: dict[str, str], channels: dict[str, dict]) -> str:
    if not text:
        return ""
    text = RE_USER_MENTION.sub(
        lambda m: f"@{users.get(m.group(1), m.group(1))}", text
    )
    text = RE_CHAN_MENTION.sub(
        lambda m: f"#{m.group(2) or channels.get(m.group(1), {}).get('name') or m.group(1)}",
        text,
    )
    text = RE_LINK.sub(
        lambda m: f"[{m.group(2) or m.group(1)}]({m.group(1)})", text
    )
    # Slack uses &amp; &lt; &gt;
    text = text.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
    return text


def ts_to_dt(ts: str) -> datetime:
    return datetime.fromtimestamp(float(ts), tz=timezone.utc).astimezone()


def render_file(f: dict, attachments_prefix: str | None) -> str:
    """Render one Slack file attachment as a markdown line."""
    fid = f.get("id", "")
    fname = f.get("name") or "file"
    mimetype = f.get("mimetype", "") or ""
    slack_url = f.get("url_private") or f.get("permalink") or ""
    if attachments_prefix and fid:
        # URL-encode each path segment separately so slashes survive.
        local = f"{attachments_prefix}/{urllib.parse.quote(fid)}/{urllib.parse.quote(fname)}"
        if mimetype.startswith("image/"):
            return f"![{fname}]({local})"
        return f"📎 [{fname}]({local})"
    # No local prefix → fall back to Slack URL (requires auth to view, but preserves the reference).
    return f"📎 [{fname}]({slack_url})" if slack_url else f"📎 {fname}"


def render_channel_by_day(
    conn: sqlite3.Connection,
    cid: str,
    title: str,
    users: dict[str, str],
    channels: dict[str, dict],
    attachments_prefix: str | None,
) -> dict[str, tuple[str, float]]:
    """Build per-day markdown bodies for one channel.

    Returns: {iso_date "YYYY-MM-DD": (body, max_load_dttm_epoch)}.
    Thread replies are attached to the day of their parent message, even
    if the reply landed on a different day — keeps threads visually
    intact rather than scattering them across days.
    """
    rows = list(
        conn.execute(
            """
            SELECT m.TS, m.TXT, m.DATA, m.IS_PARENT, m.THREAD_TS,
                   strftime('%s', m.LOAD_DTTM)
            FROM MESSAGE m
            JOIN (SELECT TS, MAX(CHUNK_ID) mx FROM MESSAGE WHERE CHANNEL_ID = ?
                  GROUP BY TS) latest
              ON m.TS = latest.TS AND m.CHUNK_ID = latest.mx
            WHERE m.CHANNEL_ID = ?
            ORDER BY CAST(m.TS AS REAL) ASC
            """,
            (cid, cid),
        )
    )

    # Split into thread replies (keyed by parent TS) and top-level messages.
    replies: dict[str, list] = defaultdict(list)
    top_level = []
    for ts, txt, data, is_parent, thread_ts, load_ts in rows:
        load_epoch = float(load_ts) if load_ts else 0.0
        entry = (ts, txt, data, bool(is_parent), load_epoch)
        if thread_ts and thread_ts != ts:
            replies[thread_ts].append(entry)
        else:
            top_level.append(entry)

    def format_msg(ts, txt, data, indent: int = 0) -> list[str]:
        try:
            d = json.loads(data)
        except (json.JSONDecodeError, TypeError):
            d = {}
        user_id = d.get("user") or d.get("bot_id") or ""
        author = users.get(user_id, d.get("username") or user_id or "unknown")
        dt = ts_to_dt(ts)
        pad = "  " * indent
        body = render_text(txt or d.get("text", ""), users, channels)
        body_lines = body.splitlines() or [""]
        lines = [f"{pad}**{author}** · {dt.strftime('%H:%M:%S')}"]
        for bl in body_lines:
            lines.append(f"{pad}{bl}" if bl else "")
        for f in d.get("files", []) or []:
            lines.append(f"{pad}{render_file(f, attachments_prefix)}")
        lines.append("")
        return lines

    # Group top-level messages by local date.
    by_day: dict[str, list[str]] = defaultdict(list)
    max_load_by_day: dict[str, float] = defaultdict(float)

    for ts, txt, data, is_parent, load_epoch in top_level:
        dt = ts_to_dt(ts)
        day = dt.strftime("%Y-%m-%d")
        if not by_day[day]:
            by_day[day].append(f"# {title} — {dt.strftime('%d-%m-%Y')}\n")
        by_day[day].extend(format_msg(ts, txt, data))
        max_load_by_day[day] = max(max_load_by_day[day], load_epoch)
        if is_parent and ts in replies:
            for r_ts, r_txt, r_data, _, r_load in sorted(
                replies[ts], key=lambda x: float(x[0])
            ):
                by_day[day].extend(format_msg(r_ts, r_txt, r_data, indent=1))
                max_load_by_day[day] = max(max_load_by_day[day], r_load)

    return {
        day: ("\n".join(lines), max_load_by_day[day])
        for day, lines in by_day.items()
    }


def main() -> int:
    positional = []
    types_filter: set[str] | None = None
    only_ids: set[str] | None = None
    for a in sys.argv[1:]:
        if a.startswith("--types="):
            types_filter = {t.strip() for t in a.split("=", 1)[1].split(",") if t.strip()}
        elif a.startswith("--only="):
            only_ids = {t.strip() for t in a.split("=", 1)[1].split(",") if t.strip()}
        else:
            positional.append(a)
    if len(positional) not in (2, 3):
        print(
            "usage: slackdump-to-md.py <archive.sqlite> <output-dir> "
            "[<attachments-prefix>] [--types=...] [--only=...]",
            file=sys.stderr,
        )
        return 2
    db_path, out_dir = positional[0], Path(positional[1])
    attachments_prefix = positional[2] if len(positional) == 3 else None
    if not Path(db_path).exists():
        print(f"warning: {db_path} not found; skipping", file=sys.stderr)
        return 0
    out_dir.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(db_path)
    try:
        users = load_users(conn)
        channels = load_channels(conn)
        # Channels that have any messages at all.
        with_msgs = {
            row[0]
            for row in conn.execute("SELECT DISTINCT CHANNEL_ID FROM MESSAGE")
        }
        rendered = skipped_fresh = skipped_identical = 0
        for cid, meta in channels.items():
            if cid not in with_msgs:
                continue
            if only_ids is not None and cid not in only_ids:
                continue
            if types_filter is not None:
                d = meta["data"]
                # Derive the channel's "type" from its boolean flags.
                kind = (
                    "im" if d.get("is_im")
                    else "mpim" if d.get("is_mpim")
                    else "private_channel" if d.get("is_private")
                    else "public_channel"
                )
                if kind not in types_filter:
                    continue
            title = channel_title(cid, meta, users)
            chan_dir = out_dir / slug(title)
            chan_dir.mkdir(parents=True, exist_ok=True)
            days = render_channel_by_day(
                conn, cid, title, users, channels, attachments_prefix
            )
            for iso_day, (body, max_load) in days.items():
                # Filename uses DD-MM-YYYY per user preference. ISO for sorting
                # would be YYYY-MM-DD; we trade chronological filename-sort for
                # the requested format.
                dd_mm_yyyy = datetime.strptime(iso_day, "%Y-%m-%d").strftime("%d-%m-%Y")
                out_path = chan_dir / f"{dd_mm_yyyy}.md"
                # Gate 1: file newer than this day's latest load → skip.
                if out_path.exists() and out_path.stat().st_mtime > max_load:
                    skipped_fresh += 1
                    continue
                # Gate 2: content unchanged → don't rewrite.
                if out_path.exists():
                    try:
                        if out_path.read_text(encoding="utf-8") == body:
                            skipped_identical += 1
                            continue
                    except OSError:
                        pass
                out_path.write_text(body, encoding="utf-8")
                rendered += 1
        print(
            f"{db_path}: rendered={rendered} skipped_fresh={skipped_fresh} "
            f"skipped_identical={skipped_identical}"
        )
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
