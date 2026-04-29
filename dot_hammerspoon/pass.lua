-- pass(1) integration: copy secrets to the clipboard without persisting them
-- in clipboard history, add new entries via a focused webview form, and
-- remove entries via a picker + confirmation.
--
-- The secret is written with UTI "org.nspasteboard.ConcealedType" in addition
-- to plain text — the clipboard watcher (clipboard/watcher.lua) skips anything
-- bearing that marker, so it never hits the cb history. The clipboard is also
-- auto-cleared after CLEAR_SECONDS to mirror `pass -c` behavior.
--
-- Public API (callable via `hs -c 'pass.X()'`):
--   pass.pick()    chooser of entries → copies selected to clipboard (concealed)
--   pass.add()     borderless webview form (name + password) → `pass insert -m`
--   pass.remove()  chooser → confirm → `pass rm -f`
--
-- Prereqs: `brew install pass gnupg pinentry-mac`, a GPG key generated,
-- `pass init <key-id>`, and pinentry-mac set in ~/.gnupg/gpg-agent.conf.

local M = {}

local PASS_BIN      = "/opt/homebrew/bin/pass"
local STORE_DIR     = os.getenv("HOME") .. "/.password-store"
local CLEAR_SECONDS = 45
local TASK_TIMEOUT  = 15  -- seconds; watchdog to prevent runaway pass procs

-- hs.task launches with a minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin), so the
-- pass script's platform.sh fails to locate `brew --prefix gnu-getopt` and
-- falls back to /usr/local/bin/getopt, which doesn't exist on Apple Silicon.
-- pass then runs its option-parsing `while true; case $1 in ... esac done`
-- with no `--` terminator, never shifts, and spins at 100% CPU forever.
local PASS_ENV = {
  PATH = "/opt/homebrew/bin:/opt/homebrew/opt/gnu-getopt/bin:/usr/bin:/bin:/usr/sbin:/sbin",
  HOME = os.getenv("HOME"),
  GNUPGHOME = os.getenv("GNUPGHOME") or (os.getenv("HOME") .. "/.gnupg"),
}

local activeTasks = {}
local function trackTask(task)
  activeTasks[task] = hs.timer.doAfter(TASK_TIMEOUT, function()
    if task:isRunning() then
      task:terminate()
      hs.alert.show("pass: command timed out", 2)
    end
    activeTasks[task] = nil
  end)
end
local function runTask(bin, args, cb)
  local task
  task = hs.task.new(bin, function(rc, out, err)
    local t = activeTasks[task]; if t then t:stop(); activeTasks[task] = nil end
    cb(rc, out, err)
  end, args)
  task:setEnvironment(PASS_ENV)
  trackTask(task)
  task:start()
  return task
end

-- ────────────────────────── helpers ──────────────────────────

local function fileExists(path)
  local f = io.open(path, "r")
  if f then f:close(); return true end
  return false
end

local function dirExists(path)
  local h = io.popen("/bin/test -d " .. string.format("%q", path) .. " && echo yes")
  if not h then return false end
  local r = h:read("*a"); h:close()
  return r and r:find("yes") ~= nil
end

local function preflight()
  if not fileExists(PASS_BIN) then
    hs.alert.show("pass not installed: brew install pass gnupg pinentry-mac", 4)
    return false
  end
  if not dirExists(STORE_DIR) then
    hs.alert.show("~/.password-store missing — run `pass init <gpg-key>`", 4)
    return false
  end
  return true
end

local function listEntries()
  local entries = {}
  local cmd = string.format(
    "/usr/bin/find %q -name '*.gpg' -type f 2>/dev/null",
    STORE_DIR
  )
  local handle = io.popen(cmd)
  if not handle then return entries end
  local prefixLen = #STORE_DIR + 2
  for path in handle:lines() do
    local name = path:sub(prefixLen):gsub("%.gpg$", "")
    if name ~= "" then table.insert(entries, name) end
  end
  handle:close()
  table.sort(entries)
  return entries
end

-- Small bottom-center toast with breathing room from the screen edge.
-- hs.alert.show's atScreenEdge pins flush to the edge, so we draw our own
-- canvas to get a proper margin.
local TOAST_MARGIN    = 48   -- px above the bottom of the screen
local TOAST_FONT_SIZE = 13
local TOAST_PAD_H     = 16
local TOAST_PAD_V     = 7
local toastCanvas, toastTimer = nil, nil

local function toast(msg, dur)
  dur = dur or 1.2
  if toastTimer then toastTimer:stop(); toastTimer = nil end
  if toastCanvas then toastCanvas:delete(); toastCanvas = nil end

  local styled = hs.styledtext.new(msg, {
    font  = { name = "SF Pro Text", size = TOAST_FONT_SIZE },
    color = { white = 1 },
  })
  local tsz = hs.drawing.getTextDrawingSize(styled) or { w = #msg * 8, h = 18 }
  local width  = math.ceil(tsz.w) + TOAST_PAD_H * 2
  local height = math.ceil(tsz.h) + TOAST_PAD_V * 2

  local screen = (hs.mouse.getCurrentScreen() or hs.screen.mainScreen()):frame()
  local frame = {
    x = screen.x + (screen.w - width) / 2,
    y = screen.y + screen.h - height - TOAST_MARGIN,
    w = width,
    h = height,
  }

  toastCanvas = hs.canvas.new(frame)
  toastCanvas:level(hs.canvas.windowLevels.overlay)
  toastCanvas:behavior({ "canJoinAllSpaces", "stationary" })
  toastCanvas[1] = {
    type = "rectangle", action = "fill",
    fillColor = { red = 0.12, green = 0.12, blue = 0.18, alpha = 0.92 },
    roundedRectRadii = { xRadius = 8, yRadius = 8 },
  }
  toastCanvas[2] = {
    type = "rectangle", action = "stroke",
    strokeColor = { white = 1, alpha = 0.18 },
    strokeWidth = 1,
    roundedRectRadii = { xRadius = 8, yRadius = 8 },
  }
  toastCanvas[3] = {
    type = "text",
    text = styled,
    textAlignment = "center",
    frame = { x = TOAST_PAD_H, y = TOAST_PAD_V - 1, w = width - TOAST_PAD_H * 2, h = tsz.h + 2 },
  }
  toastCanvas:show()

  toastTimer = hs.timer.doAfter(dur, function()
    if toastCanvas then toastCanvas:delete(); toastCanvas = nil end
    toastTimer = nil
  end)
end

local function writeConcealed(secret)
  hs.pasteboard.writeAllData({
    ["public.utf8-plain-text"]         = secret,
    ["org.nspasteboard.ConcealedType"] = secret,
  })
end

local function scheduleClear(secret)
  hs.timer.doAfter(CLEAR_SECONDS, function()
    if hs.pasteboard.getContents() == secret then
      hs.pasteboard.clearContents()
      toast("🔒 clipboard cleared")
    end
  end)
end

local function readSecret(name, callback)
  runTask(PASS_BIN, { "show", name }, function(exitCode, stdout, stderr)
    if exitCode ~= 0 then
      callback(nil, (stderr ~= "" and stderr) or ("exit " .. exitCode))
      return
    end
    local firstLine = (stdout or ""):match("^([^\r\n]*)")
    callback(firstLine, nil)
  end)
end

-- ────────────────────────── webview form ──────────────────────────
-- One shared instance at a time; replaces hs.dialog.textPrompt so the
-- form actually takes keyboard focus (hs.dialog popups don't reliably
-- activate Hammerspoon / steal focus on macOS 14+).

local formView, formUcc = nil, nil

local function closeForm()
  if formView then formView:delete(); formView = nil end
  formUcc = nil
end

local function showForm(opts)
  -- opts = { html, handler, callback, w, h }
  closeForm()
  formUcc = hs.webview.usercontent.new(opts.handler)
  formUcc:setCallback(function(msg) opts.callback(msg.body) end)

  local screen = (hs.mouse.getCurrentScreen() or hs.screen.mainScreen()):frame()
  local W, H = opts.w or 380, opts.h or 220
  formView = hs.webview.new(
    { x = screen.x + (screen.w - W) / 2,
      y = screen.y + (screen.h - H) / 2,
      w = W, h = H },
    {}, formUcc)
    :windowStyle({ "borderless" })
    :level(hs.drawing.windowLevels.floating)
    :allowTextEntry(true)
    :html(opts.html)
    :show()

  hs.timer.doAfter(0.05, function()
    if formView then
      local w = formView:hswindow()
      if w then w:raise():focus() end
    end
  end)
end

-- ────────────────────────── public API ──────────────────────────

function M.pick()
  if not preflight() then return end
  local entries = listEntries()
  if #entries == 0 then
    toast("no entries in " .. STORE_DIR)
    return
  end

  local choices = {}
  for _, name in ipairs(entries) do
    table.insert(choices, { text = name, fullName = name })
  end

  local chooser = hs.chooser.new(function(choice)
    if not choice then return end
    readSecret(choice.fullName, function(secret, err)
      if err or not secret or secret == "" then
        toast("pass: " .. tostring(err or "empty"), 2)
        return
      end
      writeConcealed(secret)
      toast("📋 " .. choice.fullName)
      scheduleClear(secret)
    end)
  end)
  chooser:choices(choices)
  chooser:placeholderText("pass entry…")
  chooser:show()
end

local ADD_HTML = [[<!DOCTYPE html><html><head><meta charset="utf-8"><style>
  :root { color-scheme: dark; }
  html, body { margin:0; padding:0; overflow:hidden; }
  body { font-family: -apple-system, system-ui; background: #1e1e2e; color: #cdd6f4;
         padding: 16px; border-radius: 10px;
         user-select: none; -webkit-user-select: none; }
  h1 { font-size: 11px; margin: 0 0 10px; font-weight: 600; opacity: 0.6;
       letter-spacing: 1px; text-transform: uppercase; }
  label { display: block; font-size: 11px; opacity: 0.7; margin: 8px 0 4px; }
  input { width: 100%; box-sizing: border-box; background: #181825;
          border: 1px solid #313244; color: #cdd6f4; font-family: inherit;
          font-size: 13px; padding: 8px 10px; border-radius: 6px; outline: none;
          user-select: auto; -webkit-user-select: auto; }
  input:focus { border-color: #89b4fa; }
  .actions { display: flex; gap: 8px; justify-content: flex-end; margin-top: 14px; }
  button { padding: 6px 12px; font-size: 13px; border: 0; border-radius: 6px;
           cursor: pointer; font-family: inherit; }
  button.primary { background: #89b4fa; color: #1e1e2e; font-weight: 600; }
  button.secondary { background: #45475a; color: #cdd6f4; }
  .hint { margin-top: 10px; font-size: 10px; opacity: 0.5; text-align: right; }
</style></head><body>
<h1>Add pass entry</h1>
<label>name</label>
<input type="text" id="name" placeholder="work/aws/prod-token" autofocus>
<label>secret</label>
<input type="password" id="secret">
<div class="actions">
  <button class="secondary" onclick="sendCancel()">Cancel</button>
  <button class="primary" onclick="sendSave()">Save</button>
</div>
<div class="hint">⎋ cancel · ⏎ next / save</div>
<script>
  const nameIn = document.getElementById('name');
  const secIn  = document.getElementById('secret');
  setTimeout(() => nameIn.focus(), 10);
  nameIn.addEventListener('keydown', e => {
    if (e.key === 'Enter') { e.preventDefault(); secIn.focus(); }
  });
  secIn.addEventListener('keydown', e => {
    if (e.key === 'Enter') { e.preventDefault(); sendSave(); }
  });
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape') sendCancel();
  });
  function sendSave() {
    const name = nameIn.value.trim(); const secret = secIn.value;
    if (!name || !secret) return;
    window.webkit.messageHandlers.passForm.postMessage({action:'save', name, secret});
  }
  function sendCancel() {
    window.webkit.messageHandlers.passForm.postMessage({action:'cancel'});
  }
</script></body></html>]]

local function savePass(name, secret, onDone)
  local escName = "'" .. name:gsub("'", "'\\''") .. "'"
  local tmp = os.tmpname()
  local f = io.open(tmp, "w")
  if not f then toast("pass: cannot write tmpfile", 2); return end
  f:write(secret); f:close()

  local cmd = string.format("%s insert -m -f %s < %s && /bin/rm -f %s",
                            PASS_BIN, escName, tmp, tmp)
  runTask("/bin/sh", { "-c", cmd }, function(exitCode, _, stderr)
    os.remove(tmp)
    if exitCode == 0 then
      toast("✅ " .. name)
    else
      toast("pass error: " .. tostring((stderr ~= "" and stderr) or ("exit " .. exitCode)), 3)
    end
    if onDone then onDone(exitCode == 0) end
  end)
end

function M.add()
  if not preflight() then return end
  -- Defer so `hs -c` IPC reply lands before the webview captures focus.
  hs.timer.doAfter(0.1, function()
    showForm({
      html    = ADD_HTML,
      handler = "passForm",
      w = 380, h = 220,
      callback = function(body)
        if type(body) ~= "table" then return end
        if body.action == "cancel" then
          closeForm()
        elseif body.action == "save" then
          local name, secret = body.name or "", body.secret or ""
          closeForm()
          if name == "" or secret == "" then return end
          savePass(name, secret)
        end
      end,
    })
  end)
end

local function confirmDeleteHTML(name)
  local escaped = name:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
  return string.format([[<!DOCTYPE html><html><head><meta charset="utf-8"><style>
  :root { color-scheme: dark; }
  html, body { margin:0; padding:0; overflow:hidden; }
  body { font-family: -apple-system, system-ui; background: #1e1e2e; color: #cdd6f4;
         padding: 18px; border-radius: 10px;
         user-select: none; -webkit-user-select: none; }
  h1 { font-size: 11px; margin: 0 0 10px; font-weight: 600; opacity: 0.6;
       letter-spacing: 1px; text-transform: uppercase; color: #f38ba8; }
  .name { font-size: 15px; font-weight: 500; padding: 10px 12px;
          background: #181825; border-radius: 6px; border-left: 3px solid #f38ba8;
          margin-bottom: 14px; word-break: break-all; }
  .actions { display: flex; gap: 8px; justify-content: flex-end; }
  button { padding: 6px 12px; font-size: 13px; border: 0; border-radius: 6px;
           cursor: pointer; font-family: inherit; }
  button.danger { background: #f38ba8; color: #1e1e2e; font-weight: 600; }
  button.secondary { background: #45475a; color: #cdd6f4; }
  .hint { margin-top: 10px; font-size: 10px; opacity: 0.5; text-align: right; }
</style></head><body>
<h1>Delete pass entry?</h1>
<div class="name">%s</div>
<div class="actions">
  <button class="secondary" onclick="sendCancel()" id="cancelBtn" autofocus>Cancel</button>
  <button class="danger" onclick="sendDelete()">Delete</button>
</div>
<div class="hint">⎋ cancel · ⏎ delete</div>
<script>
  setTimeout(() => document.getElementById('cancelBtn').focus(), 10);
  document.addEventListener('keydown', e => {
    if (e.key === 'Escape') sendCancel();
    if (e.key === 'Enter')  sendDelete();
  });
  function sendDelete() {
    window.webkit.messageHandlers.passForm.postMessage({action:'delete'});
  }
  function sendCancel() {
    window.webkit.messageHandlers.passForm.postMessage({action:'cancel'});
  }
</script></body></html>]], escaped)
end

function M.remove()
  if not preflight() then return end
  local entries = listEntries()
  if #entries == 0 then
    toast("no entries in " .. STORE_DIR)
    return
  end

  local choices = {}
  for _, name in ipairs(entries) do
    table.insert(choices, { text = name, fullName = name })
  end

  local chooser = hs.chooser.new(function(choice)
    if not choice then return end
    hs.timer.doAfter(0.1, function()
      showForm({
        html    = confirmDeleteHTML(choice.fullName),
        handler = "passForm",
        w = 380, h = 200,
        callback = function(body)
          if type(body) ~= "table" then return end
          closeForm()
          if body.action ~= "delete" then return end
          runTask(PASS_BIN, { "rm", "-f", choice.fullName }, function(exitCode, _, stderr)
            if exitCode == 0 then
              toast("🗑 " .. choice.fullName)
            else
              toast("pass rm: " .. tostring((stderr ~= "" and stderr) or ("exit " .. exitCode)), 3)
            end
          end)
        end,
      })
    end)
  end)
  chooser:choices(choices)
  chooser:placeholderText("entry to delete…")
  chooser:show()
end

return M
