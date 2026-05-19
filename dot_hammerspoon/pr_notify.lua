-- GitHub PR activity → Hammerspoon overlay alerts + on-demand picker.
--
-- Public API (callable via `hs -c 'pr_notify.X()'`):
--   pr_notify.startWatcher()   begin 2-min polling timer
--   pr_notify.stopWatcher()    stop the timer
--   pr_notify.toggleWatcher()  flip + show "ON" / "OFF" alert
--   pr_notify.checkNow()       force one immediate poll
--   pr_notify.showUpcoming()   open the centered picker of authored open PRs
--
-- Data source: ~/.local/bin/gh-pr-notify (shell script) — invoked via
-- hs.task, returns JSON array of events. All state (per-PR cursors, the
-- first-seen-at high-water-mark) lives in the shell script's cache file
-- at ~/Library/Caches/gh-pr-notify-state.json. The picker fetches PR
-- metadata directly via `gh search prs` rather than reading the cache.

local M = {}

local POLL_SECONDS   = 120
local SCRIPT_PATH    = os.getenv("HOME") .. "/.local/bin/gh-pr-notify"
local MAX_INLINE     = 4       -- after this many alerts in one tick, collapse the rest
local STAGGER_SEC    = 0.4
local RATE_LIMIT_COOLDOWN = 60 * 60  -- suppress duplicate rate-limit alerts for 1h

local watchTimer        = nil
local rateLimitedUntil  = 0

-- Per-event styling. fill = alert background, prefix = leading label.
-- textSize tuned so critical events (CI failure, changes requested) feel louder.
local STYLES = {
  approval = {
    prefix = "✓ Approved",
    textSize = 22,
    fill = { red = 0.20, green = 0.55, blue = 0.30, alpha = 0.95 },
  },
  changes_requested = {
    prefix = "✗ Changes requested",
    textSize = 24,
    fill = { red = 0.85, green = 0.45, blue = 0.15, alpha = 0.95 },
  },
  comment_review = {
    prefix = "💬 Review",
    textSize = 20,
    fill = { red = 0.20, green = 0.35, blue = 0.65, alpha = 0.95 },
  },
  issue_comment = {
    prefix = "💬 Comment",
    textSize = 20,
    fill = { red = 0.20, green = 0.35, blue = 0.65, alpha = 0.95 },
  },
  inline_comment = {
    prefix = "💬 Inline",
    textSize = 20,
    fill = { red = 0.20, green = 0.35, blue = 0.65, alpha = 0.95 },
  },
  ci_failure = {
    prefix = "⚠ CI failed",
    textSize = 26,
    fill = { red = 0.85, green = 0.25, blue = 0.30, alpha = 0.95 },
  },
}

local function fireAlert(ev)
  local style = STYLES[ev.type]
  if not style then return end

  local prRef = string.format("%s#%d", ev.repo or "?", ev.pr_number or 0)
  local title = ev.pr_title and ev.pr_title ~= "" and ev.pr_title or "(untitled)"

  local body = string.format("%s — %s", style.prefix, prRef)
  if ev.actor and ev.actor ~= "" and ev.actor ~= "ci" then
    body = body .. " · @" .. ev.actor
  end
  body = body .. "\n" .. title
  if ev.snippet and ev.snippet ~= "" then
    body = body .. "\n" .. ev.snippet
  end

  hs.alert.show(body, {
    textSize = style.textSize,
    radius = 10,
    strokeWidth = 2,
    strokeColor = { white = 1, alpha = 0.5 },
    fillColor = style.fill,
    atScreenEdge = 0,
  }, 7)

  local note = hs.notify.new(function()
    if ev.url and ev.url ~= "" then hs.urlevent.openURL(ev.url) end
  end, {
    title = style.prefix .. ": " .. prRef,
    subTitle = title,
    informativeText = (ev.actor and ev.actor ~= "" and "@" .. ev.actor .. " — " or "")
                      .. (ev.snippet or ""),
    soundName = "Purr",
    withdrawAfter = 0,
  })
  if note then note:send() end
end

local function fireSummary(extraCount)
  hs.alert.show(string.format("+ %d more PR event%s",
                              extraCount, extraCount == 1 and "" or "s"), {
    textSize = 18,
    radius = 10,
    strokeWidth = 1,
    strokeColor = { white = 1, alpha = 0.3 },
    fillColor = { red = 0.15, green = 0.15, blue = 0.2, alpha = 0.92 },
    atScreenEdge = 0,
  }, 5)
end

local function handleEvents(events)
  if type(events) ~= "table" or #events == 0 then return end

  -- Rate-limit event: throttle to once per cooldown window.
  for _, ev in ipairs(events) do
    if ev.type == "rate_limited" then
      local now = os.time()
      if now >= rateLimitedUntil then
        rateLimitedUntil = now + RATE_LIMIT_COOLDOWN
        hs.alert.show("GitHub API rate-limited\n" .. (ev.snippet or ""), {
          textSize = 20, radius = 10, strokeWidth = 2,
          strokeColor = { white = 1, alpha = 0.5 },
          fillColor = { red = 0.85, green = 0.25, blue = 0.30, alpha = 0.95 },
        }, 8)
      end
      return
    end
  end

  -- Stagger so alerts don't all stack on the same frame.
  local shown = 0
  for i, ev in ipairs(events) do
    if i > MAX_INLINE then break end
    hs.timer.doAfter((i - 1) * STAGGER_SEC, function() fireAlert(ev) end)
    shown = shown + 1
  end
  if #events > MAX_INLINE then
    hs.timer.doAfter(shown * STAGGER_SEC, function()
      fireSummary(#events - MAX_INLINE)
    end)
  end
end

local function checkAndNotify()
  hs.task.new(SCRIPT_PATH, function(exitCode, stdout, stderr)
    if exitCode ~= 0 then
      print("pr_notify: script exit " .. tostring(exitCode) .. " — " .. tostring(stderr))
      return
    end
    if not stdout or stdout == "" then return end
    local ok, events = pcall(hs.json.decode, stdout)
    if not ok then
      print("pr_notify: json decode failed: " .. tostring(events))
      return
    end
    handleEvents(events)
  end):start()
end

function M.startWatcher()
  if watchTimer then return end
  watchTimer = hs.timer.doEvery(POLL_SECONDS, checkAndNotify)
  checkAndNotify()
end

function M.stopWatcher()
  if watchTimer then
    watchTimer:stop()
    watchTimer = nil
  end
end

function M.toggleWatcher()
  if watchTimer then
    M.stopWatcher()
    hs.alert.show("PR reminders: OFF")
  else
    M.startWatcher()
    hs.alert.show("PR reminders: ON")
  end
end

function M.checkNow()
  checkAndNotify()
end

--  ──────────── On-demand picker (Leader Key → G u) ────────────

local GH_PATH         = "/opt/homebrew/bin/gh"
local PRS_CACHE_PATH  = os.getenv("HOME") .. "/Library/Caches/gh-pr-notify-prs.json"
local CACHE_STALE_SEC = 5 * 60      -- after this, kick off a background refresh
local PICKER_LIMIT    = 20          -- show at most N most-recently-updated PRs
local pickerView      = nil
local pickerUcc       = nil

-- "5m ago", "2h 30m ago", "3d ago"
local function fmtAgo(secs)
  if secs < 0 then secs = 0 end
  if secs < 60 then return secs .. "s ago" end
  local m = math.floor(secs / 60)
  if m < 60 then return m .. "m ago" end
  local h = math.floor(m / 60)
  local rem = m % 60
  if h < 24 then
    return (rem == 0) and (h .. "h ago") or string.format("%dh %dm ago", h, rem)
  end
  local d = math.floor(h / 24)
  local hr = h % 24
  return (hr == 0) and (d .. "d ago") or string.format("%dd %dh ago", d, hr)
end

-- Parse "2026-05-19T09:42:00Z" → epoch seconds. Returns 0 on failure.
local function parseISO(s)
  if not s or s == "" then return 0 end
  local y, mo, d, h, mi, se = s:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then return 0 end
  -- os.time treats the table as LOCAL time; subtract the local offset to
  -- treat the input as UTC. localtime - utctime gives the local offset.
  local utc = os.time({ year=y, month=mo, day=d, hour=h, min=mi, sec=se })
  local offset = os.difftime(os.time(), os.time(os.date("!*t")))
  return utc - offset
end

local function htmlEscape(s)
  return (s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
                  :gsub('"', "&quot;"):gsub("'", "&#39;")
end

local function buildPickerHTML(prs, err)
  local rows = {}
  for i, pr in ipairs(prs) do
    local title = (pr.title and pr.title ~= "") and pr.title or "(untitled)"
    local ago   = fmtAgo(os.time() - (pr.updatedEpoch or os.time()))
    local key   = (i <= 9) and tostring(i) or ""
    local kbd   = (key ~= "") and string.format('<kbd class="num">%s</kbd>', key) or '<span class="num-pad"></span>'
    local liClass = (i == 1) and "first" or ""
    table.insert(rows, string.format([[
<li class="%s" data-idx="%d">
  <div class="row">
    %s
    <span class="repo">%s</span>
    <span class="num">#%d</span>
    <span class="title">%s</span>
    <span class="ago">%s</span>
  </div>
</li>]],
      liClass, i - 1, kbd,
      htmlEscape(pr.repo or ""),
      pr.number or 0,
      htmlEscape(title),
      htmlEscape(ago)))
  end

  local errBlock = ""
  if err and err ~= "" then
    errBlock = string.format('<div class="error">%s</div>', htmlEscape(err))
  end
  if #prs == 0 and errBlock == "" then
    errBlock = '<div class="empty">No open PRs authored by you.</div>'
  end

  local prsForJs = {}
  for _, pr in ipairs(prs) do
    table.insert(prsForJs, { url = pr.url or "" })
  end

  return table.concat({
    [[<!DOCTYPE html><html><head><meta charset="utf-8"><style>
  :root { color-scheme: dark; }
  html, body { margin: 0; padding: 0; overflow: hidden; }
  body { font-family: -apple-system, system-ui; background: #1e1e2e; color: #cdd6f4;
         padding: 14px 16px; user-select: none; -webkit-user-select: none;
         border-radius: 10px; }
  .header { display: flex; align-items: center; justify-content: space-between;
            margin-bottom: 10px; }
  h1 { font-size: 11px; margin: 0; font-weight: 600; opacity: 0.6;
       text-transform: uppercase; letter-spacing: 1px; }
  .close { background: transparent; border: 0; color: #cdd6f4; opacity: 0.4;
           cursor: pointer; font-size: 16px; padding: 0 4px; line-height: 1; }
  .close:hover { opacity: 1; color: #f38ba8; }
  ul { list-style: none; padding: 0; margin: 0; }
  li { padding: 8px 10px; border-radius: 8px; margin-bottom: 5px; background: #181825;
       cursor: pointer; }
  li:hover { background: #313244; }
  li.first { box-shadow: inset 2px 0 0 #89b4fa; }
  .row { display: flex; gap: 10px; align-items: baseline; }
  .repo { font-size: 11px; color: #a6adc8; min-width: 0; max-width: 140px;
          overflow: hidden; text-overflow: ellipsis; white-space: nowrap; flex-shrink: 0; }
  .num { font-family: 'Menlo', ui-monospace, monospace; font-size: 12px;
         color: #89b4fa; flex-shrink: 0; }
  .title { font-size: 13px; flex: 1; overflow: hidden;
           text-overflow: ellipsis; white-space: nowrap; }
  .ago { font-size: 11px; color: #6c7086; flex-shrink: 0; }
  .error, .empty { color: #f38ba8; padding: 12px; background: rgba(243,139,168,0.08);
                   border-radius: 8px; font-size: 12px; }
  .empty { color: #a6adc8; background: rgba(166,173,200,0.06); }
  kbd { font-family: 'Menlo', ui-monospace, monospace; font-size: 10px;
        background: #313244; color: #cdd6f4; border: 1px solid #45475a;
        border-radius: 4px; padding: 1px 5px; line-height: 1;
        box-shadow: 0 1px 0 #11111b; flex-shrink: 0; }
  kbd.num { min-width: 14px; text-align: center; }
  .num-pad { display: inline-block; width: 22px; flex-shrink: 0; }
  .footer { margin-top: 10px; padding-top: 8px; border-top: 1px solid #313244;
            display: flex; gap: 14px; justify-content: flex-end; font-size: 11px;
            opacity: 0.65; }
  .footer .hint { display: inline-flex; align-items: center; gap: 5px; }
</style></head><body>
<div class="header">
  <h1>Open PRs (authored)</h1>
  <button class="close" title="Close (Esc)" onclick="window.webkit.messageHandlers.prPicker.postMessage({action:'close'})">×</button>
</div>
]],
    errBlock,
    "<ul>", table.concat(rows), "</ul>",
    #prs > 0 and
      [[<div class="footer"><span class="hint"><kbd>1</kbd>–<kbd>9</kbd> open</span><span class="hint"><kbd>d</kbd> close</span></div>]]
      or "",
    [[<script>
  const PRS = ]], hs.json.encode(prsForJs), [[;
  function open(idx) {
    const pr = PRS[idx];
    if (!pr) return;
    window.webkit.messageHandlers.prPicker.postMessage({action:'open', url: pr.url || ''});
  }
  document.querySelectorAll('li').forEach(li => {
    li.addEventListener('click', () => open(parseInt(li.dataset.idx, 10)));
  });
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape' || e.key === 'd') {
      e.preventDefault();
      window.webkit.messageHandlers.prPicker.postMessage({action:'close'});
    } else if (e.key >= '1' && e.key <= '9') {
      e.preventDefault();
      open(parseInt(e.key, 10) - 1);
    }
  });
  requestAnimationFrame(() => {
    const h = Math.ceil(document.documentElement.scrollHeight);
    window.webkit.messageHandlers.prPicker.postMessage({action: 'resize', height: h});
  });
</script></body></html>]],
  })
end

local function normalisePRs(data)
  local out = {}
  if type(data) ~= "table" then return out end
  for _, pr in ipairs(data) do
    table.insert(out, {
      url    = pr.url,
      number = pr.number,
      title  = pr.title,
      repo   = (pr.repository and pr.repository.nameWithOwner) or "",
      updatedEpoch = parseISO(pr.updatedAt or ""),
    })
  end
  table.sort(out, function(a, b)
    return (a.updatedEpoch or 0) > (b.updatedEpoch or 0)
  end)
  if #out > PICKER_LIMIT then
    for i = #out, PICKER_LIMIT + 1, -1 do out[i] = nil end
  end
  return out
end

-- Returns (prs, ageSeconds, err). prs is empty list if cache is missing.
local function readPRCache()
  local f = io.open(PRS_CACHE_PATH, "r")
  if not f then return {}, math.huge, nil end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(hs.json.decode, content)
  if not ok then return {}, math.huge, "cache parse failed" end
  local attrs = hs.fs.attributes(PRS_CACHE_PATH) or {}
  local age = (attrs.modification and (os.time() - attrs.modification)) or math.huge
  return normalisePRs(data), age, nil
end

-- Async refresh: invoke the watcher script (it rewrites the cache) and then
-- re-render the picker if it's still open. No-op if the script is busy.
local function refreshCacheAsync(onDone)
  hs.task.new(SCRIPT_PATH, function(_, _, _)
    if onDone then onDone() end
  end):start()
end

-- Fallback: direct `gh search prs` when the cache is missing entirely.
local function fetchPRsDirect(callback)
  local args = {
    "search", "prs",
    "--author=@me", "--state=open",
    "--limit", tostring(PICKER_LIMIT),
    "--json", "url,number,title,repository,updatedAt",
  }
  hs.task.new(GH_PATH, function(exitCode, stdout, stderr)
    if exitCode ~= 0 then
      callback({}, "gh search failed: " .. tostring(stderr))
      return
    end
    local ok, data = pcall(hs.json.decode, stdout or "[]")
    if not ok then
      callback({}, "json decode failed")
      return
    end
    callback(normalisePRs(data), nil)
  end, args):start()
end

local function renderPicker(prs, err)
  if pickerView then pickerView:delete(); pickerView = nil end

  pickerUcc = hs.webview.usercontent.new("prPicker")
  pickerUcc:setCallback(function(msg)
    local body = msg.body
    if type(body) ~= "table" then return end
    if body.action == "resize" and type(body.height) == "number" then
      if pickerView then
        local f = pickerView:frame()
        local newH = math.max(120, math.min(720, body.height))
        if math.abs(f.h - newH) > 2 then
          local screen = (pickerView:hswindow() and pickerView:hswindow():screen())
                         or hs.mouse.getCurrentScreen()
                         or hs.screen.mainScreen()
          local sf = screen:frame()
          pickerView:frame({
            x = sf.x + (sf.w - f.w) / 2,
            y = sf.y + (sf.h - newH) / 2,
            w = f.w, h = newH,
          })
        end
      end
    elseif body.action == "open" then
      if body.url and body.url ~= "" then hs.urlevent.openURL(body.url) end
      if pickerView then pickerView:delete(); pickerView = nil end
    elseif body.action == "close" then
      if pickerView then pickerView:delete(); pickerView = nil end
    end
  end)

  local estRowH  = 36
  local estChrome = 80
  local initH = math.max(140, math.min(720, estChrome + estRowH * math.max(1, #prs)))
  local screen = (hs.mouse.getCurrentScreen() or hs.screen.mainScreen()):frame()
  local W = 520

  pickerView = hs.webview.new(
    { x = screen.x + (screen.w - W) / 2,
      y = screen.y + (screen.h - initH) / 2,
      w = W, h = initH },
    {}, pickerUcc)
    :windowStyle({ "borderless" })
    :level(hs.drawing.windowLevels.floating)
    :allowTextEntry(true)
    :html(buildPickerHTML(prs, err))
    :show()

  hs.timer.doAfter(0.05, function()
    if pickerView then
      local w = pickerView:hswindow()
      if w then w:raise():focus() end
    end
  end)
end

function M.showUpcoming()
  local cached, age, err = readPRCache()
  if #cached > 0 then
    -- Render instantly from cache, then refresh in the background if stale.
    renderPicker(cached, nil)
    if age > CACHE_STALE_SEC then
      refreshCacheAsync(function()
        if not pickerView then return end  -- user already closed it
        local fresh = readPRCache()
        if #fresh > 0 then renderPicker(fresh, nil) end
      end)
    end
  else
    -- No cache yet (first run, never polled) — fall back to a direct call.
    fetchPRsDirect(function(prs, ferr)
      renderPicker(prs, ferr or err)
    end)
  end
end

return M
