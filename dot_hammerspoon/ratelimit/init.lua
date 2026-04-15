-- ratelimit — persistent "red banner" alerts that stay on screen until the
-- user explicitly dismisses them. Designed for situations where you want to
-- be *sure* you've seen the message (API rate limits, quota warnings, etc).
--
-- Used by ~/.local/bin/slackdump-sync when Slack returns a rate-limit error:
-- the script aborts immediately and fires this alert so the user knows to
-- stop/intervene before the next scheduled run fires.
--
-- Invoke from the CLI via:
--   hs -c 'ratelimit.show([[your message here]])'
--
-- Dismiss: Escape — the hotkey is only bound while a banner is visible,
-- so Escape works normally in every other context.

local M = {}

-- hs.canvas draws a persistent banner; hs.alert has no true "stay forever"
-- mode and disappears after its duration even if duration is huge (OS
-- compositing reclaims it). Canvas guarantees persistence until :delete().
local banner = nil
-- Escape hotkey is lazily bound on first show() and toggled via
-- :enable() / :disable() so Escape is only stolen while a banner is up.
local escHotkey = nil

function M.show(message)
  M.dismiss()  -- replace any prior banner

  local screen = hs.screen.mainScreen()
  local sf = screen:frame()
  local w, h = math.min(900, sf.w - 80), 140
  local x = sf.x + (sf.w - w) / 2
  local y = sf.y + 80
  banner = hs.canvas.new({ x = x, y = y, w = w, h = h })
  banner:level(hs.canvas.windowLevels.overlay)
  banner:behavior({"canJoinAllSpaces", "stationary"})

  banner[1] = {
    type = "rectangle",
    fillColor = { red = 0.75, green = 0.05, blue = 0.05, alpha = 0.96 },
    strokeColor = { red = 1, green = 1, blue = 1, alpha = 1 },
    strokeWidth = 3,
    roundedRectRadii = { xRadius = 14, yRadius = 14 },
  }
  banner[2] = {
    type = "text",
    text = message or "",
    textColor = { red = 1, green = 1, blue = 1 },
    textSize = 24,
    textAlignment = "center",
    textFont = "Menlo-Bold",
    frame = { x = 20, y = 20, w = w - 40, h = h - 60 },
  }
  banner[3] = {
    type = "text",
    text = "press esc to dismiss",
    textColor = { red = 1, green = 1, blue = 1, alpha = 0.75 },
    textSize = 14,
    textAlignment = "center",
    textFont = "Menlo",
    frame = { x = 20, y = h - 32, w = w - 40, h = 20 },
  }
  banner:show()

  -- Enable the Escape hotkey only while the banner is up.
  if not escHotkey then
    escHotkey = hs.hotkey.new({}, "escape", function()
      M.dismiss()
    end)
  end
  escHotkey:enable()
end

function M.dismiss()
  if banner then
    banner:delete()
    banner = nil
  end
  if escHotkey then
    escHotkey:disable()
  end
end

return M
