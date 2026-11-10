vim.cmd("edit " .. os.getenv("SAMPLE"))
require("lazy").load({ plugins = { "autocomplete-ai" } })
local st = require("lazy.core.config").plugins["autocomplete-ai"]
print("lazy plugin:", st._.loaded and "LOADED" or "not loaded")
print("C-Space insert map:", vim.fn.maparg("<C-Space>", "i", false, true).desc or "NONE")
print("ai_accept hooked:", LazyVim.cmp.actions.ai_accept ~= nil)
require("lazy").load({ plugins = { "blink.cmp" } })
local km = require("blink.cmp.config").keymap
local tab = km["<Tab>"]; print("blink Tab chain entries:", tab and #tab or "none", tab and type(tab[1]), tab and type(tab[2]))
-- simulate: a shown candidate, then LazyVim's Tab action chain
local ac = require("autocomplete"); local S = ac._state
S.buf = vim.api.nvim_get_current_buf(); S.row, S.col = 3, 40; S.candidates = { [2] = " update the key" }; S.idx = 2
local acted = LazyVim.cmp.map({ "snippet_forward", "ai_nes", "ai_accept" })()
print("Tab chain accepted:", acted, "| line:", vim.api.nvim_buf_get_lines(0, 3, 4, false)[1])
print("MESSAGES:", vim.fn.execute("messages") == "" and "none" or vim.fn.execute("messages"))
vim.cmd("qa!")
