vim.opt.rtp:prepend(vim.fn.fnamemodify(os.getenv("PLUGIN_DIR") or ".", ":p"))
local ac = require("autocomplete")
local notes = {}
vim.notify = function(msg, level) notes[#notes + 1] = (level or 0) .. ":" .. msg end
ac.setup({ url = "https://127.0.0.1:9/v1", log_file = vim.fn.tempname(), model_file = vim.fn.tempname(), timeout_s = 5 })
vim.cmd("edit " .. os.getenv("SAMPLE"))
vim.api.nvim_win_set_cursor(0, { 4, 0 }); vim.cmd("startinsert!"); vim.fn.mode = function() return "i" end
vim.schedule(ac.trigger)
local S = ac._state
vim.wait(10000, function() return S.pending == 0 and S.gen >= 1 end, 200)
print("NOTIFIES", #notes); for _, n in ipairs(notes) do print("  " .. n) end
print("idx", S.idx, "keymaps_set", S.keymaps_set, "msgs:", vim.fn.execute("messages"):gsub("\n", " | "))
-- bad key path
ac.setup({ url = "https://openrouter.ai/api/v1/chat/completions" })
vim.cmd("qa!")
