-- workspaces.lua
-- Fuzzy-searchable picker across every window in every aerospace workspace.
-- Invoked from Leader Key (leader k) via `hs -c 'workspaces.showWindowPicker()'`.

local M = {}

local AEROSPACE = "/opt/homebrew/bin/aerospace"

local function trim(s) return (s:gsub("^%s*(.-)%s*$", "%1")) end

function M.showWindowPicker()
  hs.task.new(AEROSPACE, function(exitCode, stdout, stderr)
    if exitCode ~= 0 then
      hs.alert.show("aerospace list-windows failed: " .. tostring(stderr))
      return
    end

    local choices = {}
    for line in stdout:gmatch("[^\r\n]+") do
      local id, ws, app, title = line:match("^([^|]+)|([^|]+)|([^|]+)|(.*)$")
      if id then
        local appName = trim(app)
        local icon = nil
        local running = hs.application.find(appName)
        if running then
          icon = hs.image.imageFromAppBundle(running:bundleID())
        end
        local styledTitle = hs.styledtext.new(trim(title), {
          font  = { size = 14 },
          color = { white = 0.8 },
        })
        table.insert(choices, {
          text     = string.format("[%s]  %s", trim(ws), appName),
          subText  = styledTitle,
          image    = icon,
          windowId = trim(id),
        })
      end
    end

    table.sort(choices, function(a, b)
      if a.text == b.text then return (a.subText or "") < (b.subText or "") end
      return a.text < b.text
    end)

    -- Quick-action: open a new Chrome window
    local chromeIcon = hs.image.imageFromAppBundle("com.google.Chrome")
    table.insert(choices, 1, {
      text     = "+ New Chrome Window",
      subText  = hs.styledtext.new("Open a fresh Google Chrome window", {
        font  = { size = 14 },
        color = { white = 0.8 },
      }),
      image    = chromeIcon,
      action   = "new-chrome",
    })

    local chooser = hs.chooser.new(function(choice)
      if not choice then return end
      if choice.action == "new-chrome" then
        hs.task.new("/usr/bin/open", nil, { "-na", "Google Chrome", "--args", "--new-window" }):start()
        return
      end
      hs.task.new(AEROSPACE, nil, { "focus", "--window-id", choice.windowId }):start()
    end)
    chooser:choices(choices)
    chooser:searchSubText(true)
    chooser:placeholderText("Switch to window (workspace / app / title)…")
    chooser:show()
  end, { "list-windows", "--all",
         "--format", "%{window-id}|%{workspace}|%{app-name}|%{window-title}" }):start()
end

return M
