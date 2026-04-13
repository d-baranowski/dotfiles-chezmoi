local M = {}

local tsvPath = os.getenv("HOME") .. "/.config/keybindings.tsv"
local webview = nil

local function escapeHTML(s)
  return s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;")
end

local function readTSV()
  local sections = {}
  local current = nil
  local file = io.open(tsvPath)
  if not file then return sections end

  for line in file:lines() do
    if line:match("^# ── ") then
      local title = line:match("^# ── (.-)%s*─")
      if title then
        current = { title = title, entries = {} }
        table.insert(sections, current)
      end
    elseif line:sub(1, 1) ~= "#" and line ~= "" and current then
      local _, shortcut, desc = line:match("([^\t]+)\t([^\t]+)\t([^\t]+)")
      if shortcut and desc then
        table.insert(current.entries, { shortcut = shortcut, description = desc })
      end
    end
  end

  file:close()
  return sections
end

local function generateHTML(sections)
  local rows = {}
  for _, section in ipairs(sections) do
    table.insert(rows, '<div class="section" data-section="' .. escapeHTML(section.title) .. '">')
    table.insert(rows, '  <h2>' .. escapeHTML(section.title) .. '</h2>')
    table.insert(rows, '  <table>')
    for _, e in ipairs(section.entries) do
      local search = (section.title .. " " .. e.shortcut .. " " .. e.description):lower()
      table.insert(rows, '    <tr data-s="' .. escapeHTML(search) .. '">')
      table.insert(rows, '      <td class="key">' .. escapeHTML(e.shortcut) .. '</td>')
      table.insert(rows, '      <td class="desc">' .. escapeHTML(e.description) .. '</td>')
      table.insert(rows, '    </tr>')
    end
    table.insert(rows, '  </table>')
    table.insert(rows, '</div>')
  end

  return [[<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
* { margin:0; padding:0; box-sizing:border-box; }
body {
  font-family: 'SF Mono','Menlo','Monaco',monospace;
  background: #1e1e2e; color: #cdd6f4;
  padding: 0; font-size: 15px;
}
#bar {
  position: sticky; top: 0; z-index: 10;
  background: #181825; padding: 20px 28px 14px;
  border-bottom: 1px solid #313244;
}
#bar h1 {
  font-size: 18px; font-weight: 600; color: #cdd6f4;
  margin-bottom: 12px;
}
#search {
  width: 100%; padding: 10px 14px;
  background: #313244; border: 1px solid #45475a;
  border-radius: 6px; color: #cdd6f4;
  font-family: inherit; font-size: 15px; outline: none;
}
#search:focus { border-color: #89b4fa; }
#search::placeholder { color: #6c7086; }
#hint { color: #585b70; font-size: 12px; margin-top: 8px; }
#content { padding: 10px 28px 28px; }
.section { margin-bottom: 24px; }
h2 {
  color: #89b4fa; font-size: 15px; font-weight: 600;
  padding: 10px 0 6px; margin-bottom: 4px;
  border-bottom: 1px solid #313244;
  text-transform: capitalize;
}
table { width: 100%; border-collapse: collapse; }
tr { border-bottom: 1px solid #1e1e2e; }
td { padding: 4px 0; vertical-align: top; line-height: 1.5; }
.key {
  color: #f9e2af; white-space: nowrap;
  width: 280px; padding-right: 28px;
}
.desc { color: #a6adc8; }
.hidden { display: none; }
#empty {
  display: none; color: #585b70;
  text-align: center; padding: 48px 0; font-size: 16px;
}
</style></head><body>
<div id="bar">
  <h1>Keybindings Reference</h1>
  <input type="text" id="search" placeholder="Filter keybindings..." autofocus>
  <div id="hint">Type to filter &middot; Esc to close</div>
</div>
<div id="content">
]] .. table.concat(rows, "\n") .. [[

</div>
<div id="empty">No matching keybindings</div>
<script>
const search = document.getElementById('search');
const empty = document.getElementById('empty');
search.addEventListener('input', function() {
  const q = this.value.toLowerCase().trim();
  const terms = q.split(/\s+/);
  let total = 0;
  document.querySelectorAll('.section').forEach(sec => {
    let vis = 0;
    sec.querySelectorAll('tr').forEach(tr => {
      const s = tr.getAttribute('data-s');
      const ok = !q || terms.every(t => s.includes(t));
      tr.classList.toggle('hidden', !ok);
      if (ok) vis++;
    });
    sec.classList.toggle('hidden', vis === 0);
    total += vis;
  });
  empty.style.display = total === 0 ? 'block' : 'none';
});
document.addEventListener('keydown', function(e) {
  if (e.key === 'Escape') {
    try { window.webkit.messageHandlers.keybindings.postMessage('close'); } catch(x) {}
  }
});
</script>
</body></html>]]
end

function M.show()
  if webview then
    webview:delete()
    webview = nil
  end

  local sections = readTSV()
  if #sections == 0 then
    hs.alert.show("No keybindings found — check ~/.config/keybindings.tsv")
    return
  end

  local screen = hs.screen.mainScreen():frame()
  local w = math.min(820, screen.w * 0.55)
  local h = math.min(900, screen.h * 0.8)
  local x = screen.x + (screen.w - w) / 2
  local y = screen.y + (screen.h - h) / 2

  local uc = hs.webview.usercontent.new("keybindings")
  uc:setCallback(function()
    if webview then webview:delete(); webview = nil end
  end)

  webview = hs.webview.new(
    { x = x, y = y, w = w, h = h },
    { javaScriptEnabled = true },
    uc
  )
  webview:windowTitle("Keybindings Reference")
  webview:windowStyle(
    hs.webview.windowMasks.titled +
    hs.webview.windowMasks.closable +
    hs.webview.windowMasks.resizable
  )
  webview:level(hs.drawing.windowLevels.floating)
  webview:allowTextEntry(true)
  webview:deleteOnClose(true)
  webview:html(generateHTML(sections))
  webview:show()
  webview:hswindow():focus()
end

return M
