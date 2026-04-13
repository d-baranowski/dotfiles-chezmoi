local M = {}

M.lastUsedSocket = nil

function M.findSockets()
  local tmpdir = os.getenv("TMPDIR") or "/tmp/"
  local user = os.getenv("USER")
  local pattern = tmpdir .. "nvim." .. user .. "/*/0"

  local sockets = {}
  local handle = io.popen("ls " .. pattern .. " 2>/dev/null")
  if handle then
    for line in handle:lines() do
      table.insert(sockets, line)
    end
    handle:close()
  end
  return sockets
end

function M.isAlive(socket)
  local cmd = string.format(
    "nvim --server %s --remote-expr '1' 2>/dev/null",
    socket
  )
  local handle = io.popen(cmd)
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("1") ~= nil
end

function M.findLiveSockets()
  local all = M.findSockets()
  local live = {}
  for _, sock in ipairs(all) do
    if M.isAlive(sock) then
      table.insert(live, sock)
    end
  end
  return live
end

function M.describe(socket)
  local cmd = string.format(
    [[nvim --server %s --remote-expr 'getcwd() . "|" . expand("%%:t")' 2>/dev/null]],
    socket
  )
  local handle = io.popen(cmd)
  if not handle then return socket end
  local result = handle:read("*a"):gsub("%s+$", "")
  handle:close()

  local cwd, file = result:match("([^|]+)|(.*)")
  if not cwd then return socket end

  local home = os.getenv("HOME")
  if home then cwd = cwd:gsub("^" .. home:gsub("([%.%-%+])", "%%%1"), "~") end

  if file == "" then return cwd end
  return cwd .. " -- " .. file
end

function M.queryRegister(socket, letter)
  local cmd = string.format(
    [[nvim --server %s --remote-expr 'getreg("%s")' 2>/dev/null]],
    socket, letter
  )
  local handle = io.popen(cmd)
  if not handle then return nil end
  local result = handle:read("*a"):gsub("%s+$", "")
  handle:close()
  return result
end

function M.pickSocket(callback, opts)
  opts = opts or {}
  local live = M.findLiveSockets()

  if #live == 0 then
    hs.alert.show("No running Neovim instances")
    return
  end

  if #live == 1 then
    M.lastUsedSocket = live[1]
    callback(live[1])
    return
  end

  if opts.remember and M.lastUsedSocket then
    for _, sock in ipairs(live) do
      if sock == M.lastUsedSocket then
        callback(sock)
        return
      end
    end
  end

  local choices = {}
  for _, sock in ipairs(live) do
    table.insert(choices, {
      text = M.describe(sock),
      subText = sock,
      socket = sock,
    })
  end

  local chooser = hs.chooser.new(function(choice)
    if not choice then return end
    M.lastUsedSocket = choice.socket
    callback(choice.socket)
  end)
  chooser:choices(choices)
  chooser:show()
end

return M
