local M = {}

local CTL = os.getenv("HOME") .. "/.local/bin/slackdump-sync-ctl"
local HTML_PATH = os.getenv("HOME") .. "/.hammerspoon/slacksync/ui.html"

local webview = nil
local runTask = nil

-- ── ctl invocation ────────────────────────────────────────────────────

local function escapeShell(s)
  return "'" .. (s:gsub("'", "'\\''")) .. "'"
end

local function ctlOneShot(args, cb)
  local cmd = CTL
  for _, a in ipairs(args) do cmd = cmd .. " " .. escapeShell(a) end
  cmd = cmd .. " 2>&1"
  hs.task.new("/bin/sh", function(rc, stdout, stderr)
    local out = (stdout or "") .. (stderr or "")
    if rc ~= 0 then
      cb(nil, "ctl exit " .. tostring(rc) .. ": " .. out); return
    end
    local ok, decoded = pcall(hs.json.decode, out)
    if not ok or type(decoded) ~= "table" then
      cb(nil, "could not decode ctl output: " .. out); return
    end
    cb(decoded, nil)
  end, { "-c", cmd }):start()
end

-- ── JS bridge ─────────────────────────────────────────────────────────

local function jsCall(fn, payload)
  if not webview then return end
  local ok, json = pcall(hs.json.encode, payload or {})
  if not ok then return end
  pcall(function()
    webview:evaluateJavaScript(string.format("window._sync && window._sync.%s(%s);", fn, json))
  end)
end

local actions = {}

function actions.list_chats()
  ctlOneShot({ "list-chats" }, function(data, err)
    if err then jsCall("onError", { error = err }); return end
    jsCall("onChats", data)
  end)
end

function actions.enqueue(msg)
  ctlOneShot({ "enqueue", "--workspace", msg.workspace, "--channel", msg.channel },
    function(_, err)
      if err then jsCall("onError", { error = err }); return end
      actions.list_chats()
    end)
end

function actions.dequeue(msg)
  ctlOneShot({ "dequeue", "--workspace", msg.workspace, "--channel", msg.channel },
    function(_, err)
      if err then jsCall("onError", { error = err }); return end
      actions.list_chats()
    end)
end

function actions.clear_queue(_)
  ctlOneShot({ "clear-queue" }, function(_, err)
    if err then jsCall("onError", { error = err }); return end
    actions.list_chats()
  end)
end

function actions.run_queue(_)
  if runTask and runTask:isRunning() then
    jsCall("onError", { error = "run-queue already in flight" }); return
  end
  jsCall("onRunStart", {})
  local buf = ""
  runTask = hs.task.new("/bin/sh", function(rc, _, stderr)
    runTask = nil
    if rc ~= 0 then jsCall("onRunDone", { ok = false, error = stderr or ("rc=" .. rc) }) end
    actions.list_chats()
  end, function(_, stdout, _)
    buf = buf .. (stdout or "")
    while true do
      local nl = buf:find("\n", 1, true); if not nl then break end
      local line = buf:sub(1, nl - 1); buf = buf:sub(nl + 1)
      if line ~= "" then
        local ok, evt = pcall(hs.json.decode, line)
        if ok and type(evt) == "table" then
          jsCall("onRunEvent", evt)
          if evt.event == "done" then hs.timer.doAfter(0.2, actions.list_chats) end
        end
      end
    end
    return true
  end, { "-c", CTL .. " run-queue 2>&1" })
  runTask:start()
end

function actions.close(_) M.close() end

-- ── HTML loader ───────────────────────────────────────────────────────

local function loadHTML()
  local f = io.open(HTML_PATH)
  if not f then
    return "<html><body style='background:#1e1e2e;color:#f38ba8;padding:20px;font-family:monospace'>"
        .. "ui.html not found at " .. HTML_PATH .. "</body></html>"
  end
  local s = f:read("*a"); f:close()
  return s
end

-- ── show/close ────────────────────────────────────────────────────────

function M.show()
  -- Always rebuild from scratch. The previous webview may have been closed
  -- via the title bar (deleteOnClose nukes the userdata), so :delete() can
  -- raise "attempt to index a userdata value" — pcall it.
  if webview then
    pcall(function() webview:delete() end)
    webview = nil
  end

  local screen = hs.screen.mainScreen():frame()
  local w = math.min(1100, screen.w * 0.7)
  local h = math.min(820,  screen.h * 0.85)
  local x = screen.x + (screen.w - w) / 2
  local y = screen.y + (screen.h - h) / 2

  local uc = hs.webview.usercontent.new("slacksync")
  uc:setCallback(function(msg)
    local body = msg.body
    if type(body) == "string" then
      local ok, decoded = pcall(hs.json.decode, body)
      if ok then body = decoded end
    end
    if type(body) ~= "table" or not body.action then return end
    local fn = actions[body.action]
    if fn then fn(body) end
  end)

  webview = hs.webview.new(
    { x = x, y = y, w = w, h = h },
    { javaScriptEnabled = true },
    uc
  )
  webview:windowTitle("Slack Sync")
  webview:windowStyle(
    hs.webview.windowMasks.titled +
    hs.webview.windowMasks.closable +
    hs.webview.windowMasks.resizable
  )
  webview:level(hs.drawing.windowLevels.floating)
  webview:allowTextEntry(true)
  webview:deleteOnClose(true)
  webview:html(loadHTML())
  webview:show()
  if webview:hswindow() then webview:hswindow():focus() end

  hs.timer.doAfter(0.15, actions.list_chats)
end

function M.close()
  if webview then
    pcall(function() webview:delete() end)
    webview = nil
  end
end

return M
