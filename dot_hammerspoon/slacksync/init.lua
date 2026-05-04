-- slacksync — manual Slack sync UI.
--
-- Opens a webview lister of known chats across all configured Slack
-- workspaces, with per-chat last-synced timestamps and queue actions.
-- Slack APIs are only hit when the user explicitly presses "Run Queue".
--
-- Backend: ~/.local/bin/slackdump-sync-ctl (Python).
-- Config:  ~/Library/Application Support/slackdump-sync/workspaces.toml
--
-- Public API:
--   slacksync.show()   open the picker (idempotent)
--   slacksync.close()  close it

local picker = require("slacksync.picker")

local M = {}

function M.show()  picker.show()  end
function M.close() picker.close() end

return M
