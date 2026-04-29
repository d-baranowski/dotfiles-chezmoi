-- Ask Haiku: fire-and-forget one-off question to Claude Haiku.
--
-- Public API (callable via `hs -c 'ask_haiku.show()'`):
--   ask_haiku.show()   open the floating ask-Haiku window
--
-- Flow: floating webview with input field → submit → `claude -p --model haiku`
-- runs in a dedicated empty workdir → response rendered in same window.
-- Uses Claude Code's OAuth/subscription auth (no API key). Each call takes
-- ~2-3s of startup overhead before Haiku responds.
--
-- Keybindings inside the window:
--   Enter           submit prompt (when input focused)
--   Esc             close window
--   y               copy last response to clipboard
--   j / ArrowDown   scroll response down
--   k / ArrowUp     scroll response up
--   g               jump to top of response
--   G               jump to bottom of response
--   /               refocus input (ask something else)

local M = {}

local CLAUDE_BIN = os.getenv("HOME") .. "/.local/bin/claude"
local WORKDIR    = os.getenv("HOME") .. "/.hammerspoon/ask_haiku_workdir"

local webview = nil
local ucc     = nil
local task    = nil

local function ensureWorkdir()
  hs.fs.mkdir(WORKDIR)
end

local function killTask()
  if task then
    pcall(function() task:terminate() end)
    task = nil
  end
end

local function closeWebview()
  killTask()
  if webview then webview:delete(); webview = nil end
  ucc = nil
end

local function htmlEscape(s)
  return (s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
                  :gsub('"', "&quot;"):gsub("'", "&#39;")
end

-- Push a JS expression into the current webview. Used to stream back state
-- changes (loading, response, error) from Lua → JS.
local function evalJS(js)
  if webview then webview:evaluateJavaScript(js) end
end

local function runClaude(prompt)
  killTask()
  ensureWorkdir()

  local args = {
    "-p",
    "--model", "haiku",
    "--no-session-persistence",
    "--disable-slash-commands",
    "--append-system-prompt",
    "Be concise and direct. Give a focused one-shot answer without asking "
      .. "followup questions.",
    prompt,
  }

  task = hs.task.new(CLAUDE_BIN, function(exitCode, stdout, stderr)
    task = nil
    if not webview then return end
    local payload = hs.json.encode({
      ok   = exitCode == 0,
      text = stdout or "",
      err  = stderr or "",
    })
    evalJS("window.__askHaiku.handleResponse(" .. payload .. ")")
  end, args)

  task:setWorkingDirectory(WORKDIR)
  task:start()
end

local HTML = [[<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
  :root { color-scheme: dark; }
  html, body { margin: 0; padding: 0; height: 100%; overflow: hidden; }
  body { font-family: -apple-system, system-ui; background: #1e1e2e;
         color: #cdd6f4; border-radius: 10px; }
  .container { display: flex; flex-direction: column; height: 100vh; }
  .header { display: flex; align-items: center; justify-content: space-between;
            padding: 10px 14px 8px; }
  h1 { font-size: 11px; margin: 0; font-weight: 600; opacity: 0.6;
       text-transform: uppercase; letter-spacing: 1px; }
  .model-badge { font-size: 10px; opacity: 0.5; font-family: Menlo, ui-monospace, monospace; }
  .input-area { padding: 0 14px 10px; }
  #prompt { width: 100%; box-sizing: border-box; background: #181825;
            color: #cdd6f4; border: 1px solid #45475a; border-radius: 6px;
            padding: 8px 10px; font-family: inherit; font-size: 13px;
            resize: none; outline: none; line-height: 1.4; }
  #prompt:focus { border-color: #89b4fa; }
  #prompt::placeholder { color: #6c7086; }
  .response-area { flex: 1; overflow-y: auto; padding: 12px 14px;
                   border-top: 1px solid #313244; background: #181825;
                   outline: none; }
  .response-area::-webkit-scrollbar { width: 6px; }
  .response-area::-webkit-scrollbar-thumb { background: #45475a; border-radius: 3px; }
  #response { white-space: pre-wrap; font-size: 13px; line-height: 1.55;
              word-wrap: break-word; }
  #response code { font-family: Menlo, ui-monospace, monospace; font-size: 12px;
                   background: #313244; padding: 1px 5px; border-radius: 3px; }
  #response pre { background: #11111b; padding: 10px 12px; border-radius: 6px;
                  overflow-x: auto; font-family: Menlo, ui-monospace, monospace;
                  font-size: 12px; line-height: 1.5; margin: 8px 0; }
  #response pre code { background: transparent; padding: 0; }
  .loading { opacity: 0.55; font-style: italic; }
  .loading::after { content: ''; display: inline-block; width: 6px; height: 6px;
                    border-radius: 50%; background: #89b4fa; margin-left: 6px;
                    animation: pulse 1s ease-in-out infinite; vertical-align: middle; }
  @keyframes pulse { 0%, 100% { opacity: 0.3 } 50% { opacity: 1 } }
  .error { color: #f38ba8; padding: 8px 10px; background: rgba(243,139,168,0.08);
           border-radius: 6px; white-space: pre-wrap; font-family: Menlo, monospace;
           font-size: 12px; }
  .empty { color: #6c7086; font-style: italic; font-size: 12px; }
  .footer { padding: 6px 14px; border-top: 1px solid #313244;
            font-size: 10px; opacity: 0.55; display: flex; gap: 12px;
            justify-content: flex-end; align-items: center; }
  .footer .status { margin-right: auto; font-style: italic; color: #a6e3a1; }
  kbd { font-family: Menlo, ui-monospace, monospace; font-size: 9px;
        background: #313244; color: #cdd6f4; border: 1px solid #45475a;
        border-radius: 3px; padding: 1px 4px; line-height: 1; }
</style></head><body>
<div class="container">
  <div class="header">
    <h1>Ask Haiku</h1>
    <span class="model-badge">claude-haiku-4-5</span>
  </div>
  <div class="input-area">
    <textarea id="prompt" rows="2" placeholder="Ask anything… (Enter to send, Esc to close)" autofocus></textarea>
  </div>
  <div class="response-area" id="response-area" tabindex="-1">
    <div id="response"><span class="empty">Response will appear here.</span></div>
  </div>
  <div class="footer">
    <span class="status" id="status"></span>
    <span><kbd>y</kbd> copy</span>
    <span><kbd>j</kbd>/<kbd>k</kbd> scroll</span>
    <span><kbd>/</kbd> ask again</span>
    <span><kbd>Esc</kbd> close</span>
  </div>
</div>

<script>
(function() {
  const prompt    = document.getElementById('prompt');
  const response  = document.getElementById('response');
  const respArea  = document.getElementById('response-area');
  const statusEl  = document.getElementById('status');
  let lastText = '';
  let isLoading = false;

  function send(action, extra) {
    const msg = Object.assign({action: action}, extra || {});
    window.webkit.messageHandlers.askHaiku.postMessage(msg);
  }

  function flashStatus(text, ms) {
    statusEl.textContent = text;
    setTimeout(() => { if (statusEl.textContent === text) statusEl.textContent = ''; }, ms || 1500);
  }

  // Very small markdown-ish renderer: fenced code blocks and inline backticks.
  // Everything else stays as plain text (white-space: pre-wrap preserves newlines).
  function render(text) {
    const esc = s => s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    const parts = text.split(/```/);
    let out = '';
    for (let i = 0; i < parts.length; i++) {
      if (i % 2 === 1) {
        const chunk = parts[i].replace(/^[a-zA-Z0-9_+-]*\n/, '');
        out += '<pre><code>' + esc(chunk) + '</code></pre>';
      } else {
        out += esc(parts[i]).replace(/`([^`\n]+)`/g, '<code>$1</code>');
      }
    }
    return out;
  }

  function submit() {
    const text = prompt.value.trim();
    if (!text || isLoading) return;
    isLoading = true;
    response.innerHTML = '<span class="loading">Thinking</span>';
    lastText = '';
    statusEl.textContent = '';
    prompt.blur();
    respArea.focus();
    send('submit', {prompt: text});
  }

  function close() { send('close'); }

  function copyResponse() {
    if (!lastText) return;
    send('copy', {text: lastText});
    flashStatus('copied');
  }

  window.__askHaiku = {
    handleResponse: function(result) {
      isLoading = false;
      if (result.ok && result.text) {
        lastText = result.text.trim();
        response.innerHTML = render(lastText);
      } else if (result.ok) {
        lastText = '';
        response.innerHTML = '<span class="empty">(empty response)</span>';
      } else {
        lastText = '';
        const e = (result.err || '').trim() || 'claude -p failed';
        response.innerHTML = '<div class="error">' +
          e.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;') + '</div>';
      }
      respArea.focus();
    }
  };

  prompt.addEventListener('keydown', e => {
    if (e.key === 'Enter' && !e.shiftKey && !e.metaKey) {
      e.preventDefault(); submit();
    } else if (e.key === 'Escape') {
      e.preventDefault(); close();
    }
  });

  // Global keys take effect only when the input is not focused, so typing
  // "y" or "j" in the prompt still works as normal text entry.
  document.addEventListener('keydown', e => {
    if (document.activeElement === prompt) return;
    if (e.key === 'Escape') { e.preventDefault(); close(); return; }
    if (e.key === 'y') { e.preventDefault(); copyResponse(); return; }
    if (e.key === 'j' || e.key === 'ArrowDown') {
      e.preventDefault();
      respArea.scrollBy({top: 60, behavior: 'smooth'}); return;
    }
    if (e.key === 'k' || e.key === 'ArrowUp') {
      e.preventDefault();
      respArea.scrollBy({top: -60, behavior: 'smooth'}); return;
    }
    if (e.key === 'g' && !e.shiftKey) {
      e.preventDefault(); respArea.scrollTop = 0; return;
    }
    if (e.key === 'G' || (e.key === 'g' && e.shiftKey)) {
      e.preventDefault(); respArea.scrollTop = respArea.scrollHeight; return;
    }
    if (e.key === '/' || e.key === 'i') {
      e.preventDefault(); prompt.focus(); prompt.select(); return;
    }
  });

  prompt.focus();
})();
</script></body></html>]]

function M.show()
  closeWebview()

  ucc = hs.webview.usercontent.new("askHaiku")
  ucc:setCallback(function(msg)
    local body = msg.body
    if type(body) ~= "table" then return end
    if body.action == "submit" and type(body.prompt) == "string" then
      runClaude(body.prompt)
    elseif body.action == "close" then
      closeWebview()
    elseif body.action == "copy" then
      hs.pasteboard.setContents(body.text or "")
    end
  end)

  local screen = (hs.mouse.getCurrentScreen() or hs.screen.mainScreen()):frame()
  local W, H = 680, 480
  local frame = {
    x = screen.x + (screen.w - W) / 2,
    y = screen.y + (screen.h - H) / 2,
    w = W,
    h = H,
  }

  webview = hs.webview.new(frame, {}, ucc)
    :windowStyle({ "titled", "closable", "nonactivating" })
    :windowTitle("Ask Haiku")
    :level(hs.drawing.windowLevels.floating)
    :allowTextEntry(true)
    :closeOnEscape(false)  -- we handle Esc in JS so copy feedback stays visible
    :html(HTML)
    :show()

  hs.timer.doAfter(0.05, function()
    if webview then
      local w = webview:hswindow()
      if w then w:raise():focus() end
    end
  end)
end

return M
