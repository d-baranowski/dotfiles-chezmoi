#!/usr/bin/env python3
"""
Parse icalBuddy output (from stdin) into a JSON events cache at argv[1].

Why this exists: Hammerspoon.app lacks NSCalendarsFullAccessUsageDescription
in its Info.plist, so EventKit requests from hs.task-spawned children are
silently denied on macOS 14+. sketchybar already has Full Calendar Access, so
we run icalBuddy under sketchybar and dump the result to a shared cache file
that Hammerspoon's calendar.lua reads without needing its own TCC grant.

icalBuddy invocation expected upstream (no -npn, so named props carry prefixes):
  icalBuddy -sc -n -nc -ea -nrd -tf '%H:%M' -df '%Y-%m-%d' \\
            -iep 'title,datetime,location,url,notes' -b '§§' eventsToday+1
"""
import sys, re, json, os
from datetime import datetime

if len(sys.argv) < 2:
    sys.stderr.write("usage: calendar_cache.py <cache_path>\n")
    sys.exit(1)

cache_path = sys.argv[1]
raw = sys.stdin.read()

DATE_RE = re.compile(
    r"^(\d{4}-\d{2}-\d{2})\s+at\s+"
    r"(\d{2}:\d{2})"
    r"(?:\s*-\s*(?:(\d{4}-\d{2}-\d{2})\s+)?(\d{2}:\d{2}))?$"
)
# Match Meet / Zoom / Teams / Webex / generic https:// URLs embedded in notes.
MEET_URL_RE = re.compile(
    r"https?://(?:meet\.google\.com|zoom\.us|[\w.-]+\.zoom\.us|teams\.microsoft\.com|"
    r"[\w.-]+\.webex\.com)[^\s<>\"']*"
)
ANY_URL_RE = re.compile(r"https?://[^\s<>\"']+")

events = []
current = None
calendar_name = ""

def pick_url(notes, url):
    if url: return url
    if not notes: return ""
    m = MEET_URL_RE.search(notes)
    if m: return m.group(0)
    m = ANY_URL_RE.search(notes)
    return m.group(0) if m else ""

for line in raw.splitlines():
    # Calendar section header: "<name>:" at column 0, not an event bullet
    if line and not line.startswith(" ") and not line.startswith("§§") and line.endswith(":"):
        if current and current.get("date") and current.get("start"):
            events.append(current)
        calendar_name = line[:-1].rstrip()
        current = None
        continue
    if line.startswith("---"):
        continue
    if line.startswith("§§"):
        if current and current.get("date") and current.get("start"):
            events.append(current)
        current = {
            "title": line[2:].strip(),
            "calendar": calendar_name,
            "date": None, "start": None, "end": None, "end_date": None,
            "location": "", "url": "", "notes": "",
        }
        continue
    if current is None:
        continue
    stripped = line.strip()
    m = DATE_RE.match(stripped)
    if m:
        current["date"] = m.group(1)
        current["start"] = m.group(2)
        current["end_date"] = m.group(3) or m.group(1)
        current["end"] = m.group(4) or m.group(2)
        continue
    # Named properties: "location: ...", "url: ...", "notes: ..."
    if stripped.startswith("location:"):
        current["location"] = stripped[len("location:"):].strip()
    elif stripped.startswith("url:"):
        current["url"] = stripped[len("url:"):].strip()
    elif stripped.startswith("notes:"):
        current["notes"] = stripped[len("notes:"):].strip()
    elif current.get("notes") is not None and not DATE_RE.match(stripped):
        # Continuation of a multi-line notes block (icalBuddy wraps long text).
        current["notes"] = (current["notes"] + " " + stripped).strip()

if current and current.get("date") and current.get("start"):
    events.append(current)

now = datetime.now()
out = []
for e in events:
    try:
        start_dt = datetime.strptime(f"{e['date']} {e['start']}", "%Y-%m-%d %H:%M")
    except (ValueError, TypeError):
        continue
    try:
        end_dt = (datetime.strptime(f"{e['end_date']} {e['end']}", "%Y-%m-%d %H:%M")
                  if e.get("end") else start_dt)
    except (ValueError, TypeError):
        end_dt = start_dt
    out.append({
        "uid": f"{e['date']}T{e['start']}_{(e['title'] or '')[:60]}",
        "summary": e["title"],
        "startEpoch": int(start_dt.timestamp()),
        "endEpoch": int(end_dt.timestamp()),
        "startLocalStr": e["start"],
        "endLocalStr": e["end"] or e["start"],
        "calendar": e["calendar"],
        "location": e["location"],
        "url": pick_url(e.get("notes", ""), e.get("url", "")),
    })

out.sort(key=lambda x: x["startEpoch"])

os.makedirs(os.path.dirname(cache_path), exist_ok=True)
tmp = cache_path + ".tmp"
with open(tmp, "w") as f:
    json.dump({"events": out, "writtenAtEpoch": int(now.timestamp())},
              f, separators=(",", ":"), ensure_ascii=False)
os.replace(tmp, cache_path)
