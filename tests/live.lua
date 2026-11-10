vim.opt.rtp:prepend(vim.fn.fnamemodify(os.getenv("PLUGIN_DIR") or ".", ":p"))
local ac = require("autocomplete")
ac.setup({ log_file = vim.fn.tempname(), model_file = vim.fn.tempname() })
vim.cmd("edit " .. os.getenv("SAMPLE"))
vim.api.nvim_win_set_cursor(0, { 4, 0 })
vim.cmd("startinsert!"); vim.fn.mode = function() return "i" end
vim.schedule(ac.trigger)
local S = ac._state
local t0 = vim.uv.now()
vim.wait(20000, function() return S.pending == 0 and S.gen == 1 end, 200)
print("ELAPSED_MS", vim.uv.now() - t0, "shown idx", S.idx, "pending", S.pending, "gen", S.gen)
for i = 1, 3 do print(string.format("CAND %d (%s): %q", i, ac.config.lengths[i].name, tostring(S.candidates[i]))) end
-- cycle and accept the long one
ac.show(3); print("STATUS:", vim.fn.execute("messages"):gsub("\n", " | "))
ac.accept()
print("LINES AFTER ACCEPT:"); for _, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do print("  " .. l) end
print("extmarks left:", #vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("ai_autocomplete"), 0, -1, {}))
vim.cmd("qa!")
