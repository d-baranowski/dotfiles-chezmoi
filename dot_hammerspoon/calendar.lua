-- Calendar integration: persist "important" calendar list + webview picker UI.
--
-- Public API (callable via `hs -c 'calendar.X()'`):
--   calendar.pickImportant()  open checkbox UI to select important calendars
--   calendar.getImportant()   -> { "Cal A", "Cal B" }  currently selected names
--
-- Persistence: hs.settings key "calendar.important" (NSUserDefaults-backed).
-- Calendar data source: osascript / Calendar.app (Apple Events automation).
-- This path is used because Hammerspoon.app's Info.plist does not declare
-- NSCalendarsFullAccessUsageDescription, so direct EventKit access (via
-- icalBuddy) is silently denied on macOS 14+ with no user-visible prompt.
-- osascript is Apple-signed for automation and triggers a proper TCC prompt
-- ("Hammerspoon would like to control Calendar") which appears under
-- System Settings → Privacy & Security → Automation → Hammerspoon.
-- Side effect: Calendar.app is launched in the background on each lookup.

local M = {}

local SETTINGS_KEY = "calendar.important"
local OSASCRIPT    = "/usr/bin/osascript"

local webview = nil
local ucc     = nil

function M.getImportant()
  return hs.settings.get(SETTINGS_KEY) or {}
end

local function setImportant(list)
  hs.settings.set(SETTINGS_KEY, list or {})
end

local function listCalendars(callback)
  -- JXA: emits a JSON array of calendar names via Calendar.app. De-duplicated
  -- because multiple Google accounts can each subscribe to the same shared
  -- calendar (e.g. "Holidays in Poland"), which would otherwise appear 3x.
  local jxa = [[
    var app = Application('Calendar');
    var names = app.calendars.name();
    var seen = {}, out = [];
    for (var i = 0; i < names.length; i++) {
      var n = names[i];
      if (!seen[n]) { seen[n] = true; out.push(n); }
    }
    JSON.stringify(out);
  ]]
  hs.task.new(OSASCRIPT, function(exitCode, stdout, stderr)
    local calendars = {}
    if exitCode == 0 and stdout and stdout ~= "" then
      local ok, decoded = pcall(hs.json.decode, stdout)
      if ok and type(decoded) == "table" then calendars = decoded end
    end
    callback(calendars, stderr)
  end, { "-l", "JavaScript", "-e", jxa }):start()
end

local function buildHTML(calendars, importantSet, err)
  local errorBlock = ""
  if err and err ~= "" then
    local safe = err:gsub("<", "&lt;"):gsub(">", "&gt;")
    errorBlock = string.format('<div class="error">%s</div>', safe)
  end
  if #calendars == 0 then
    errorBlock = errorBlock .. [[
<div class="error">
  No calendars found.<br>
  Grant automation access: System Settings → Privacy &amp; Security → Automation → Hammerspoon → Calendar.
</div>]]
  end

  return table.concat({
    [[<!DOCTYPE html><html><head><meta charset="utf-8"><style>
  :root { color-scheme: dark; }
  body { font-family: -apple-system, system-ui; background: #1e1e2e; color: #cdd6f4;
         padding: 16px; margin: 0; user-select: none; -webkit-user-select: none; }
  h1 { font-size: 11px; margin: 0 0 12px; font-weight: 600; opacity: 0.6;
       text-transform: uppercase; letter-spacing: 1px; }
  ul { list-style: none; padding: 0; margin: 0 0 12px; }
  li { padding: 6px 10px; border-radius: 6px; }
  li:hover { background: #313244; }
  label { display: flex; align-items: center; gap: 10px; cursor: pointer; font-size: 13px; }
  input[type=checkbox] { accent-color: #89b4fa; width: 15px; height: 15px; margin: 0; }
  .actions { display: flex; gap: 8px; justify-content: flex-end;
             border-top: 1px solid #313244; padding-top: 12px; }
  button { padding: 6px 14px; font-size: 13px; border: 0; border-radius: 6px;
           cursor: pointer; font-family: inherit; }
  button.primary { background: #89b4fa; color: #1e1e2e; font-weight: 600; }
  button.primary:hover { background: #b4befe; }
  button.secondary { background: #45475a; color: #cdd6f4; }
  button.secondary:hover { background: #585b70; }
  .error { color: #f38ba8; padding: 10px 12px; background: rgba(243,139,168,0.08);
           border-radius: 6px; margin-bottom: 12px; font-size: 12px; line-height: 1.5; }
  .hint { opacity: 0.5; font-size: 11px; margin-top: 8px; text-align: right; }
</style></head><body>
<h1>Important calendars</h1>
]],
    errorBlock,
    [[<ul id="list"></ul>
<div class="actions">
  <button class="secondary" onclick="sendCancel()">Cancel (⎋)</button>
  <button class="primary" onclick="sendSave()">Save (⏎)</button>
</div>
<div class="hint">Selected calendars will drive event reminder popups.</div>
<script>
  const calendars = ]], hs.json.encode(calendars), [[;
  const importantSet = ]], hs.json.encode(importantSet), [[;
  const list = document.getElementById('list');
  calendars.forEach((name) => {
    const li = document.createElement('li');
    const label = document.createElement('label');
    const cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.checked = !!importantSet[name];
    cb.dataset.name = name;
    label.appendChild(cb);
    label.appendChild(document.createTextNode(' ' + name));
    li.appendChild(label);
    list.appendChild(li);
  });
  function sendSave() {
    const selected = Array.from(document.querySelectorAll('input[type=checkbox]:checked'))
      .map(c => c.dataset.name);
    window.webkit.messageHandlers.calendar.postMessage({action: 'save', selected});
  }
  function sendCancel() {
    window.webkit.messageHandlers.calendar.postMessage({action: 'cancel'});
  }
  document.addEventListener('keydown', e => {
    if (e.key === 'Enter')  { e.preventDefault(); sendSave(); }
    if (e.key === 'Escape') { e.preventDefault(); sendCancel(); }
  });
</script></body></html>]],
  })
end

local function closeWebview()
  if webview then
    webview:delete()
    webview = nil
  end
  ucc = nil
end

function M.pickImportant()
  listCalendars(function(calendars, err)
    local importantList = M.getImportant()
    local importantSet  = {}
    for _, n in ipairs(importantList) do importantSet[n] = true end

    closeWebview()

    ucc = hs.webview.usercontent.new("calendar")
    ucc:setCallback(function(msg)
      local body = msg.body
      if type(body) == "table" and body.action == "save" then
        local selected = body.selected or {}
        setImportant(selected)
        hs.alert.show("Saved " .. #selected .. " important calendar" ..
                      (#selected == 1 and "" or "s"))
        closeWebview()
      elseif type(body) == "table" and body.action == "cancel" then
        closeWebview()
      end
    end)

    local screen = hs.screen.mainScreen():frame()
    local W, H = 420, 520
    local frame = {
      x = screen.x + (screen.w - W) / 2,
      y = screen.y + (screen.h - H) / 2,
      w = W,
      h = H,
    }

    webview = hs.webview.new(frame, {}, ucc)
      :windowTitle("Important Calendars")
      :windowStyle({ "titled", "closable" })
      :level(hs.drawing.windowLevels.floating)
      :allowTextEntry(true)
      :html(buildHTML(calendars, importantSet, err))
      :show()

    hs.timer.doAfter(0.05, function()
      if webview then
        local w = webview:hswindow()
        if w then w:raise():focus() end
      end
    end)
  end)
end

--  ──────────── Upcoming events + reminder watcher ────────────

local LEAD_MINUTES      = { 15, 5, 1 }  -- alert thresholds before event start
local POLL_SECONDS      = 60            -- watcher poll cadence
local WATCH_HORIZON_MIN = 20            -- events further than this are ignored per tick
local SHOW_HORIZON_MIN  = 24 * 60       -- showUpcoming default lookahead
local PAST_BUFFER_MIN   = 30            -- keep "just missed" events at the top
local CACHE_PATH        = os.getenv("HOME") .. "/Library/Caches/hammerspoon-calendar-events.json"

local watchTimer    = nil
local notifiedKeys  = {}   -- [uid .. "_" .. lead] = true; dedupes alerts
local upcomingView  = nil
local upcomingUcc   = nil

-- Reads the shared events cache written by sketchybar's calendar_event.sh.
-- (Direct EventKit access from Hammerspoon is silently denied because the
-- app bundle lacks NSCalendarsFullAccessUsageDescription. Sketchybar has
-- the grant, so we piggyback on its icalBuddy run for recurring-safe data.)
function M.getUpcoming(horizonMin, callback)
  horizonMin = horizonMin or SHOW_HORIZON_MIN
  local f = io.open(CACHE_PATH, "r")
  if not f then
    callback({}, "no cache yet at " .. CACHE_PATH ..
                 " — is sketchybar running with Calendar access?")
    return
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(hs.json.decode, content)
  if not ok or type(data) ~= "table" or type(data.events) ~= "table" then
    callback({}, "cache parse failed")
    return
  end

  local important = M.getImportant()
  local importantSet, filterOn = {}, #important > 0
  for _, n in ipairs(important) do importantSet[n] = true end

  local now = os.time()
  local horizonSec = horizonMin * 60
  local pastBufSec = PAST_BUFFER_MIN * 60
  local out = {}
  for _, ev in ipairs(data.events) do
    local startEpoch = tonumber(ev.startEpoch) or 0
    local endEpoch   = tonumber(ev.endEpoch) or startEpoch
    local secs = startEpoch - now
    -- Include if:
    --   • just-missed / upcoming window: start is within [-PAST_BUFFER, +horizon], OR
    --   • still in progress: started earlier but hasn't ended yet
    local inWindow = secs >= -pastBufSec and secs <= horizonSec
    local ongoing  = startEpoch <= now and endEpoch > now
    if inWindow or ongoing then
      if (not filterOn) or importantSet[ev.calendar or ""] then
        ev.secondsUntilStart = secs
        ev.isOngoing = (startEpoch <= now and endEpoch > now)
        table.insert(out, ev)
      end
    end
  end
  table.sort(out, function(a, b)
    return (a.secondsUntilStart or 0) < (b.secondsUntilStart or 0)
  end)
  callback(out, nil)
end

local function fireAlert(ev, lead, minsLeft)
  local msg = string.format("%s min → %s", lead, ev.summary ~= "" and ev.summary or "(untitled)")
  if ev.location and ev.location ~= "" then msg = msg .. "\n" .. ev.location end
  if ev.startLocalStr and ev.startLocalStr ~= "" then
    msg = msg .. "\n" .. ev.startLocalStr
  end
  local textSize = (lead <= 1 and 30) or (lead <= 5 and 22) or 18
  local fill = (lead <= 1)
    and { red = 0.85, green = 0.25, blue = 0.3, alpha = 0.95 }
    or  { red = 0.15, green = 0.15, blue = 0.2, alpha = 0.92 }
  hs.alert.show(msg, {
    textSize = textSize,
    radius = 10,
    strokeWidth = 2,
    strokeColor = { white = 1, alpha = 0.5 },
    fillColor = fill,
    atScreenEdge = 0,
  }, 6)
  hs.notify.new({
    title = "Upcoming: " .. (ev.summary ~= "" and ev.summary or "(untitled)"),
    informativeText = string.format("In %d min (%s)", lead, ev.startLocalStr or ""),
    soundName = "Purr",
    withdrawAfter = 0,
  }):send()
end

local function checkAndNotify()
  if #M.getImportant() == 0 then return end  -- watcher idle until calendars selected
  M.getUpcoming(WATCH_HORIZON_MIN, function(events, err)
    if err then
      print("calendar watcher error:", err)
      return
    end
    for _, ev in ipairs(events) do
      local minsUntil = (ev.secondsUntilStart or 0) / 60
      for _, lead in ipairs(LEAD_MINUTES) do
        local key = (ev.uid or "?") .. "_" .. lead
        if minsUntil > 0 and minsUntil <= lead and not notifiedKeys[key] then
          notifiedKeys[key] = true
          fireAlert(ev, lead, minsUntil)
        end
      end
    end
  end)
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
    hs.alert.show("Calendar reminders: OFF")
  else
    M.startWatcher()
    hs.alert.show("Calendar reminders: ON")
  end
end

local function fmtCountdown(secs)
  if secs >= -30 and secs < 60 then return "now" end
  local past = secs < 0
  local abs  = math.abs(secs)
  local out
  if abs < 60 then
    out = abs .. "s"
  else
    local m = math.floor(abs / 60)
    if m < 60 then
      out = m .. "m"
    else
      local h = math.floor(m / 60)
      local rem = m % 60
      out = (rem == 0) and (h .. "h") or string.format("%dh %dm", h, rem)
    end
  end
  return past and ("-" .. out) or out
end

local function htmlEscape(s)
  return (s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
                  :gsub('"', "&quot;"):gsub("'", "&#39;")
end

local function buildUpcomingHTML(events, err, horizonMin)
  local rows = {}
  for i, ev in ipairs(events) do
    local title = (ev.summary and ev.summary ~= "") and ev.summary or "(untitled)"
    local cd = fmtCountdown(ev.secondsUntilStart or 0)
    local hasUrl = ev.url and ev.url ~= ""
    local iconTitle = hasUrl and "Open meeting link" or "Open in Calendar"
    local iconGlyph = hasUrl and "↗" or "◧"
    local liClasses = {}
    if i == 1 then table.insert(liClasses, "first") end
    if ev.isOngoing then
      table.insert(liClasses, "ongoing")
    elseif (ev.secondsUntilStart or 0) < 0 then
      table.insert(liClasses, "past")
    end
    local liClass = table.concat(liClasses, " ")
    local jHint   = (i == 1) and '<kbd class="inline">j</kbd>' or ""
    table.insert(rows, string.format([[
<li class="%s" data-idx="%d">
  <div class="row">
    <span class="time">%s</span>
    <span class="title">%s</span>
    %s
    <button class="link" title="%s" data-action="open" data-idx="%d">%s</button>
  </div>
  <div class="meta">%s · %s%s</div>
</li>]],
      liClass,
      i - 1,
      htmlEscape(ev.startLocalStr or ""),
      htmlEscape(title),
      jHint,
      htmlEscape(iconTitle),
      i - 1,
      iconGlyph,
      cd,
      htmlEscape(ev.calendar or ""),
      ev.location and ev.location ~= "" and (" · " .. htmlEscape(ev.location)) or ""))
  end

  local errBlock = ""
  if err and err ~= "" then
    errBlock = string.format('<div class="error">%s</div>', htmlEscape(err))
  end
  if #events == 0 and errBlock == "" then
    errBlock = '<div class="empty">No events in the next ' ..
               math.floor(horizonMin / 60) .. 'h on your important calendars.</div>'
  end

  -- Minimal event payload for JS click handler (URLs & Calendar.app fallback).
  local evForJs = {}
  for _, ev in ipairs(events) do
    table.insert(evForJs, {
      url = ev.url or "",
      startEpoch = ev.startEpoch or 0,
    })
  end

  return table.concat({
    [[<!DOCTYPE html><html><head><meta charset="utf-8"><style>
  :root { color-scheme: dark; }
  html, body { margin: 0; padding: 0; overflow: hidden; }
  body { font-family: -apple-system, system-ui; background: #1e1e2e; color: #cdd6f4;
         padding: 14px 16px 14px 16px; user-select: none; -webkit-user-select: none;
         border-radius: 10px; }
  .header { display: flex; align-items: center; justify-content: space-between;
            margin-bottom: 10px; }
  h1 { font-size: 11px; margin: 0; font-weight: 600; opacity: 0.6;
       text-transform: uppercase; letter-spacing: 1px; }
  .close { background: transparent; border: 0; color: #cdd6f4; opacity: 0.4;
           cursor: pointer; font-size: 16px; padding: 0 4px; line-height: 1; }
  .close:hover { opacity: 1; color: #f38ba8; }
  ul { list-style: none; padding: 0; margin: 0; }
  li { padding: 10px 12px; border-radius: 8px; margin-bottom: 6px; background: #181825; }
  .row { display: flex; gap: 12px; align-items: baseline; }
  .time { font-family: 'Menlo', ui-monospace, monospace; font-size: 13px;
          color: #89b4fa; min-width: 48px; }
  .title { font-size: 14px; font-weight: 500; flex: 1; overflow: hidden;
           text-overflow: ellipsis; white-space: nowrap; }
  .link { background: transparent; border: 1px solid #45475a; color: #cdd6f4;
          width: 26px; height: 26px; border-radius: 6px; cursor: pointer;
          font-size: 13px; line-height: 1; padding: 0; display: inline-flex;
          align-items: center; justify-content: center; flex-shrink: 0; }
  .link:hover { background: #313244; border-color: #89b4fa; color: #89b4fa; }
  .meta { font-size: 11px; opacity: 0.55; margin-top: 4px; padding-left: 60px; }
  .error, .empty { color: #f38ba8; padding: 12px; background: rgba(243,139,168,0.08);
                   border-radius: 8px; font-size: 12px; }
  .empty { color: #a6adc8; background: rgba(166,173,200,0.06); }

  /* Keyboard-shortcut visual cues */
  li.first { box-shadow: inset 2px 0 0 #89b4fa; }
  /* Time-based cues */
  li.past    .time { color: #6c7086; }             /* started ago, presumably ended */
  li.past    .title { opacity: 0.7; }
  li.ongoing { box-shadow: inset 2px 0 0 #a6e3a1; } /* green accent: in progress */
  li.ongoing .time { color: #a6e3a1; }
  li.first.ongoing { box-shadow: inset 2px 0 0 #a6e3a1, inset 4px 0 0 #89b4fa; }
  kbd { font-family: 'Menlo', ui-monospace, monospace; font-size: 10px;
        background: #313244; color: #cdd6f4; border: 1px solid #45475a;
        border-radius: 4px; padding: 1px 5px; line-height: 1;
        box-shadow: 0 1px 0 #11111b; }
  kbd.inline { flex-shrink: 0; opacity: 0.85; }
  .footer { margin-top: 10px; padding-top: 8px; border-top: 1px solid #313244;
            display: flex; gap: 14px; justify-content: flex-end; font-size: 11px;
            opacity: 0.65; }
  .footer .hint { display: inline-flex; align-items: center; gap: 5px; }
</style></head><body>
<div class="header">
  <h1>Upcoming events</h1>
  <button class="close" title="Close (Esc)" onclick="window.webkit.messageHandlers.calendarUpcoming.postMessage({action:'close'})">×</button>
</div>
]],
    errBlock,
    "<ul>", table.concat(rows), "</ul>",
    #events > 0 and
      [[<div class="footer"><span class="hint"><kbd>j</kbd> open</span><span class="hint"><kbd>d</kbd> close</span></div>]]
      or "",
    [[<script>
  const EVENTS = ]], hs.json.encode(evForJs), [[;
  document.querySelectorAll('button.link').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault(); e.stopPropagation();
      const idx = parseInt(btn.dataset.idx, 10);
      const ev = EVENTS[idx] || {};
      window.webkit.messageHandlers.calendarUpcoming.postMessage({
        action: 'open', url: ev.url || '', startEpoch: ev.startEpoch || 0,
      });
    });
  });
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape' || e.key === 'd') {
      e.preventDefault();
      window.webkit.messageHandlers.calendarUpcoming.postMessage({action:'close'});
    } else if (e.key === 'j') {
      e.preventDefault();
      const ev = EVENTS[0];
      if (ev) {
        window.webkit.messageHandlers.calendarUpcoming.postMessage({
          action: 'open', url: ev.url || '', startEpoch: ev.startEpoch || 0,
        });
      }
    }
  });
  // Report exact rendered height so Lua can resize the window to fit.
  requestAnimationFrame(() => {
    const h = Math.ceil(document.documentElement.scrollHeight);
    window.webkit.messageHandlers.calendarUpcoming.postMessage({action: 'resize', height: h});
  });
</script></body></html>]],
  })
end

-- Open Calendar.app to the given epoch date using the calshow: URL scheme.
-- calshow: expects seconds since Apple reference date (2001-01-01 UTC).
local APPLE_EPOCH_OFFSET = 978307200  -- seconds between 1970-01-01 and 2001-01-01
local function openInCalendarApp(epoch)
  if not epoch or epoch <= 0 then
    hs.execute("open -a 'Calendar'")
    return
  end
  local appleTs = tonumber(epoch) - APPLE_EPOCH_OFFSET
  hs.urlevent.openURL("calshow:" .. math.floor(appleTs))
end

function M.showUpcoming(horizonMin)
  horizonMin = horizonMin or SHOW_HORIZON_MIN
  M.getUpcoming(horizonMin, function(events, err)
    if upcomingView then upcomingView:delete(); upcomingView = nil end

    upcomingUcc = hs.webview.usercontent.new("calendarUpcoming")
    upcomingUcc:setCallback(function(msg)
      local body = msg.body
      if type(body) ~= "table" then return end
      if body.action == "resize" and type(body.height) == "number" then
        if upcomingView then
          local f = upcomingView:frame()
          -- Borderless window: content height == window height (no chrome).
          local newH = math.max(120, math.min(720, body.height))
          if math.abs(f.h - newH) > 2 then
            -- Re-center on the screen that currently holds the window so the
            -- panel stays visually centered after auto-sizing.
            local screen = (upcomingView:hswindow() and upcomingView:hswindow():screen())
                           or hs.mouse.getCurrentScreen()
                           or hs.screen.mainScreen()
            local sf = screen:frame()
            upcomingView:frame({
              x = sf.x + (sf.w - f.w) / 2,
              y = sf.y + (sf.h - newH) / 2,
              w = f.w,
              h = newH,
            })
          end
        end
      elseif body.action == "open" then
        if body.url and body.url ~= "" then
          hs.urlevent.openURL(body.url)
        else
          openInCalendarApp(body.startEpoch)
        end
      elseif body.action == "close" then
        if upcomingView then upcomingView:delete(); upcomingView = nil end
      end
    end)

    -- Rough pre-render sizing (JS will post an exact height shortly after).
    local estRowH  = 62
    local estChrome = 70
    local initH = math.max(140, math.min(720, estChrome + estRowH * math.max(1, #events)))

    -- Center on the screen the cursor is on (best proxy for "where the user is looking").
    local screen = (hs.mouse.getCurrentScreen() or hs.screen.mainScreen()):frame()
    local W = 460
    upcomingView = hs.webview.new(
      { x = screen.x + (screen.w - W) / 2,
        y = screen.y + (screen.h - initH) / 2,
        w = W, h = initH },
      {}, upcomingUcc)
      :windowStyle({ "borderless" })
      :level(hs.drawing.windowLevels.floating)
      :allowTextEntry(true)
      :html(buildUpcomingHTML(events, err, horizonMin))
      :show()

    hs.timer.doAfter(0.05, function()
      if upcomingView then
        local w = upcomingView:hswindow()
        if w then w:raise():focus() end
      end
    end)
  end)
end

return M
