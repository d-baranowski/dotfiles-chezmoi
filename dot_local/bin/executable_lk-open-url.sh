#!/usr/bin/env bash
# Open clipboard contents as a URL in Chrome. Fall back to aerospace workspace I.
# Permissive URL check: trimmed, single line, no whitespace, and either starts
# with http(s):// or contains a dot (treats "example.com", "foo.dev/bar" as URLs).

set -u

clip=$(pbpaste 2>/dev/null | tr -d '\r')
# Take first non-empty line, trim whitespace
url=$(printf '%s' "$clip" | awk 'NF{print; exit}' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

is_url=0
if [ -n "$url" ] && ! printf '%s' "$url" | grep -q '[[:space:]]'; then
  if printf '%s' "$url" | grep -qiE '^(https?|ftp|file)://.+'; then
    is_url=1
  elif printf '%s' "$url" | grep -qE '^[A-Za-z0-9._~%+-]+\.[A-Za-z0-9._~%+/?#=&-]+$'; then
    is_url=1
  fi
fi

if [ "$is_url" = 1 ]; then
  # Add https:// if no scheme present
  if ! printf '%s' "$url" | grep -qiE '^[a-z][a-z0-9+.-]*://'; then
    url="https://$url"
  fi
  exec open -a "Google Chrome" "$url"
else
  exec /opt/homebrew/bin/aerospace workspace I
fi
