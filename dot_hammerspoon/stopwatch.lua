-- Stopwatch overlay: small unobtrusive timer in the bottom-right corner.
-- Controlled from Leader Key (see config.json, group "x").
--
-- Public API (all callable via `hs -c 'stopwatch.X()'`):
--   stopwatch.start()   start or resume counting; shows overlay
--   stopwatch.stop()    pause counting; overlay stays visible
--   stopwatch.reset()   zero the elapsed time; keeps running state
--   stopwatch.toggle()  start if stopped, stop if running
--   stopwatch.hide()    hide overlay entirely (also stops)

local M = {}

local canvas    = nil
local tickTimer = nil
local running   = false
local elapsed   = 0       -- seconds accumulated while running
local startedAt = nil     -- hs.timer.secondsSinceEpoch() when last resumed

local WIDTH, HEIGHT = 120, 34
local MARGIN        = 16

local function currentElapsed()
  if running and startedAt then
    return elapsed + (hs.timer.secondsSinceEpoch() - startedAt)
  end
  return elapsed
end

local function fmt(secs)
  secs = math.floor(secs)
  local h = math.floor(secs / 3600)
  local m = math.floor((secs % 3600) / 60)
  local s = secs % 60
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s)
  end
  return string.format("%02d:%02d", m, s)
end

local function ensureCanvas()
  if canvas then return end
  local screen = hs.screen.mainScreen():fullFrame()
  local frame = {
    x = screen.x + screen.w - WIDTH - MARGIN,
    y = screen.y + screen.h - HEIGHT - MARGIN,
    w = WIDTH,
    h = HEIGHT,
  }
  canvas = hs.canvas.new(frame)
  canvas:level(hs.canvas.windowLevels.overlay)
  canvas:behavior({ "canJoinAllSpaces", "stationary" })

  canvas[1] = {
    type = "rectangle",
    action = "fill",
    fillColor = { red = 0, green = 0, blue = 0, alpha = 0.55 },
    roundedRectRadii = { xRadius = 8, yRadius = 8 },
  }
  canvas[2] = {
    type = "text",
    text = "00:00",
    textSize = 18,
    textColor = { white = 1.0, alpha = 0.95 },
    textFont = "Menlo-Bold",
    textAlignment = "center",
    frame = { x = 0, y = 6, w = WIDTH, h = HEIGHT - 6 },
  }
  -- Small "running/paused" dot in the corner.
  canvas[3] = {
    type = "circle",
    action = "fill",
    center = { x = 10, y = 10 },
    radius = 3,
    fillColor = { red = 0.3, green = 0.3, blue = 0.3, alpha = 0.9 },
  }
end

local function render()
  ensureCanvas()
  canvas[2].text = fmt(currentElapsed())
  if running then
    canvas[3].fillColor = { red = 0.2, green = 0.9, blue = 0.3, alpha = 0.95 }
  else
    canvas[3].fillColor = { red = 0.9, green = 0.6, blue = 0.2, alpha = 0.9 }
  end
  canvas:show()
end

local function startTicker()
  if tickTimer then return end
  tickTimer = hs.timer.doEvery(0.5, render)
end

local function stopTicker()
  if tickTimer then
    tickTimer:stop()
    tickTimer = nil
  end
end

function M.start()
  if not running then
    startedAt = hs.timer.secondsSinceEpoch()
    running = true
  end
  render()
  startTicker()
end

function M.stop()
  if running then
    elapsed = elapsed + (hs.timer.secondsSinceEpoch() - startedAt)
    startedAt = nil
    running = false
  end
  render()
  stopTicker()
end

function M.reset()
  elapsed = 0
  if running then
    startedAt = hs.timer.secondsSinceEpoch()
  end
  render()
end

function M.toggle()
  if running then M.stop() else M.start() end
end

function M.hide()
  stopTicker()
  running = false
  startedAt = nil
  if canvas then
    canvas:hide()
    canvas:delete()
    canvas = nil
  end
end

return M
