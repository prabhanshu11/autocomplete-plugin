-- AI autocomplete for Neovim, backed by OpenRouter.
--
-- One trigger key in insert mode asks for THREE candidate completions of different
-- length for the same cursor position (short / medium / long). The first one to
-- arrive is shown as ghost text; <leader>h / <leader>l (or <leader>1/2/3) switch
-- between lengths while the ghost text is visible, Tab accepts, typing dismisses.
-- Failures (offline, bad key, dead model) are ONE quiet warning, never an error trace.

local M = {}

local ns = vim.api.nvim_create_namespace("ai_autocomplete")
local LOG_LEVELS = vim.log.levels

---------------------------------------------------------------------------
-- Configuration
---------------------------------------------------------------------------
M.config = {
  url = "https://openrouter.ai/api/v1/chat/completions",
  models_url = "https://openrouter.ai/api/v1/models",
  -- Resolved lazily: $OPENROUTER_API_KEY, else `pass show api/openrouter`.
  api_key = nil,
  model = "anthropic/claude-haiku-5.5",
  -- Curated list shown first in the model picker (prices as of 2026-11-10, USD per 1M tokens).
  models = {
    { id = "anthropic/claude-haiku-5.5", note = "fast, cheap; in 0.10 / out 0.50" },
    { id = "google/gemini-2.5-flash-lite", note = "cheapest Gemini; in 0.10 / out 0.40" },
    { id = "google/gemini-3.1-flash-lite", note = "newer Gemini lite; in 0.25 / out 1.50" },
    { id = "openai/gpt-5-nano", note = "cheapest OpenAI; in 0.05 / out 0.40" },
    { id = "openai/gpt-5-mini", note = "in 0.25 / out 2.00" },
    { id = "qwen/qwen3-coder-flash", note = "code-tuned; in 0.20 / out 0.98" },
    { id = "mistralai/codestral-2508", note = "code-tuned; in 0.30 / out 0.90" },
    { id = "moonshotai/kimi-k2.7-code", note = "code-tuned; in 0.60 / out 3.50" },
    { id = "deepseek/deepseek-chat", note = "in 0.32 / out 0.89" },
  },
  temperature = 0.3,
  timeout_s = 20,
  context = { before = 80, after = 30 }, -- lines of context sent around the cursor
  lengths = {
    { name = "short", max_tokens = 32,
      instruction = "Complete only the current word or phrase: at most about 6 words. Never go past the end of the current sentence or line." },
    { name = "medium", max_tokens = 100,
      instruction = "Complete the current sentence, line or statement. One line; two at most if the line is clearly mid-statement." },
    { name = "long", max_tokens = 400,
      instruction = "Continue the text for the next 3 to 8 lines: finish the current thought and write the next logical step in the same style." },
  },
  default_length = 2, -- medium
  keymaps = {
    trigger = "<C-Space>", -- insert mode, always
    -- Insert mode, only while ghost text is visible (so Space stays a plain Space otherwise):
    shorter = "<leader>h",
    longer = "<leader>l",
    pick = { "<leader>1", "<leader>2", "<leader>3" },
    model = "<leader>m",
    dismiss = "<C-e>",
    -- Normal mode, always:
    model_normal = "<leader>am",
  },
  hl = "Comment",
  log_file = vim.fn.stdpath("data") .. "/autocomplete-log.jsonl",
  model_file = vim.fn.stdpath("data") .. "/autocomplete-model",
  system_prompt = table.concat({
    "You are an inline autocomplete engine inside a text editor.",
    "You receive the text before and after the cursor. Reply with ONLY the text to insert at the cursor:",
    "no explanation, no quotes, no markdown fences, no leading label.",
    "Never repeat text that is already before the cursor. Match the language, style, indentation and tone of the surrounding text.",
    "If the text is prose or notes, continue the prose; if it is code, continue the code.",
  }, " "),
}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local S = {
  gen = 0,          -- request generation; replies from older generations are dropped
  buf = nil,
  row = nil, col = nil,
  candidates = {},  -- index -> text
  idx = nil,        -- which candidate is shown
  extmark = nil,
  keymaps_set = false,
  accepting = false,
  warned = false,   -- one warning per generation
  pending = 0,
  started = nil,
}

local function echo(msg, hl)
  vim.api.nvim_echo({ { msg, hl or "ModeMsg" } }, false, {})
end

local function warn(msg)
  vim.notify("AI autocomplete: " .. msg, LOG_LEVELS.WARN, { title = "AI autocomplete" })
end

local function log(event)
  local f = io.open(M.config.log_file, "a")
  if not f then return end
  event.ts = os.date("!%Y-%m-%dT%H:%M:%SZ")
  f:write(vim.json.encode(event), "\n")
  f:close()
end

---------------------------------------------------------------------------
-- API key
---------------------------------------------------------------------------
local key_cache
local function get_key()
  if key_cache then return key_cache end
  local env = os.getenv("OPENROUTER_API_KEY")
  if env and env ~= "" then key_cache = env; return key_cache end
  if M.config.api_key and M.config.api_key ~= "" then key_cache = M.config.api_key; return key_cache end
  local ok, res = pcall(function()
    return vim.system({ "timeout", "8", "pass", "show", "api/openrouter" }, { text = true }):wait()
  end)
  if ok and res and res.code == 0 then
    local line = (res.stdout or ""):match("^[^\n]*")
    if line and line ~= "" then key_cache = line; return key_cache end
  end
  return nil
end

---------------------------------------------------------------------------
-- Model persistence
---------------------------------------------------------------------------
local function load_model()
  local f = io.open(M.config.model_file, "r")
  if not f then return end
  local m = (f:read("*l") or ""):gsub("%s+$", "")
  f:close()
  if m ~= "" then M.config.model = m end
end

function M.set_model(id)
  M.config.model = id
  local f = io.open(M.config.model_file, "w")
  if f then f:write(id, "\n"); f:close() end
  vim.notify("AI autocomplete model: " .. id, LOG_LEVELS.INFO, { title = "AI autocomplete" })
  log({ event = "model", model = id })
end

---------------------------------------------------------------------------
-- Ghost text
---------------------------------------------------------------------------
local function clear(opts)
  opts = opts or {}
  if S.extmark and S.buf and vim.api.nvim_buf_is_valid(S.buf) then
    pcall(vim.api.nvim_buf_del_extmark, S.buf, ns, S.extmark)
  end
  S.extmark = nil
  if S.keymaps_set and S.buf and vim.api.nvim_buf_is_valid(S.buf) then
    local km = M.config.keymaps
    for _, lhs in ipairs({ km.shorter, km.longer, km.model, km.dismiss, km.pick[1], km.pick[2], km.pick[3] }) do
      pcall(vim.keymap.del, "i", lhs, { buffer = S.buf })
    end
    if not M._lazyvim_tab then pcall(vim.keymap.del, "i", "<Tab>", { buffer = S.buf }) end
    S.keymaps_set = false
  end
  if not opts.keep then
    S.candidates, S.idx = {}, nil
    S.gen = S.gen + 1 -- drops any reply still in flight
    S.pending = 0
    echo("")
  end
end

local function status_line()
  local parts = {}
  for i, l in ipairs(M.config.lengths) do
    local mark = S.candidates[i] and "" or "…"
    local name = l.name .. mark
    if i == S.idx then name = "[" .. name .. "]" end
    parts[#parts + 1] = name
  end
  local km = M.config.keymaps
  local leader = (vim.g.mapleader == " " or vim.g.mapleader == nil) and "Space " or vim.g.mapleader
  local function k(lhs) return (lhs:gsub("<[Ll]eader>", leader)) end
  return string.format("AI %s  %s  Tab accept · %s/%s length · %s model · %s dismiss",
    M.config.model:match("[^/]+$"), table.concat(parts, " "), k(km.shorter), k(km.longer), k(km.model), k(km.dismiss))
end

local function set_keymaps()
  if S.keymaps_set then return end
  local km = M.config.keymaps
  local o = { buffer = S.buf, silent = true, desc = "AI autocomplete" }
  vim.keymap.set("i", km.shorter, function() M.cycle(-1) end, o)
  vim.keymap.set("i", km.longer, function() M.cycle(1) end, o)
  for i, lhs in ipairs(km.pick) do
    vim.keymap.set("i", lhs, function() M.show(i) end, o)
  end
  vim.keymap.set("i", km.model, function() M.pick_model() end, o)
  vim.keymap.set("i", km.dismiss, function() clear() end, o)
  if not M._lazyvim_tab then
    vim.keymap.set("i", "<Tab>", function() M.accept() end, o)
  end
  S.keymaps_set = true
end

function M.show(i)
  if not S.buf or not vim.api.nvim_buf_is_valid(S.buf) then return end
  S.idx = i
  local text = S.candidates[i]
  if S.extmark then pcall(vim.api.nvim_buf_del_extmark, S.buf, ns, S.extmark); S.extmark = nil end
  if text then
    local lines = vim.split(text, "\n", { plain = true })
    local opts = {
      virt_text = { { lines[1], M.config.hl } },
      virt_text_pos = "inline",
      hl_mode = "combine",
    }
    if #lines > 1 then
      opts.virt_lines = {}
      for j = 2, #lines do opts.virt_lines[#opts.virt_lines + 1] = { { lines[j], M.config.hl } } end
    end
    S.extmark = vim.api.nvim_buf_set_extmark(S.buf, ns, S.row, S.col, opts)
    set_keymaps()
  end
  echo(status_line())
end

function M.cycle(dir)
  if not S.idx then return end
  local n = #M.config.lengths
  M.show(((S.idx - 1 + dir) % n) + 1)
end

function M.accept()
  local text = S.idx and S.candidates[S.idx]
  if not text or not S.buf or not vim.api.nvim_buf_is_valid(S.buf) then return false end
  local lines = vim.split(text, "\n", { plain = true })
  S.accepting = true
  pcall(vim.api.nvim_buf_set_text, S.buf, S.row, S.col, S.row, S.col, lines)
  local end_row = S.row + #lines - 1
  local end_col = (#lines == 1) and (S.col + #lines[1]) or #lines[#lines]
  pcall(vim.api.nvim_win_set_cursor, 0, { end_row + 1, end_col })
  log({ event = "accept", model = M.config.model, length = M.config.lengths[S.idx].name, chars = #text })
  clear()
  vim.schedule(function() S.accepting = false end)
  return true
end

---------------------------------------------------------------------------
-- Request
---------------------------------------------------------------------------
local function context_text(buf, row, col)
  local c = M.config.context
  local first = math.max(0, row - c.before)
  local before_lines = vim.api.nvim_buf_get_lines(buf, first, row + 1, false)
  local cur = before_lines[#before_lines] or ""
  before_lines[#before_lines] = cur:sub(1, col)
  local after_lines = vim.api.nvim_buf_get_lines(buf, row, row + 1 + c.after, false)
  after_lines[1] = (after_lines[1] or ""):sub(col + 1)
  return table.concat(before_lines, "\n"), table.concat(after_lines, "\n")
end

local function tidy(text, before)
  if not text then return nil end
  text = text:gsub("^%s*```[%w_-]*\n", ""):gsub("\n```%s*$", "")
  text = text:gsub("\n+$", "")
  -- Models often echo the tail of the text before the cursor; strip the longest such echo.
  local tail = before:sub(-60)
  for n = #tail, 1, -1 do
    local piece = tail:sub(-n)
    if text:sub(1, n) == piece then text = text:sub(n + 1); break end
  end
  if text:match("^%s*$") then return nil end
  -- Models often drop the space between the word before the cursor and the first new word.
  if before:sub(-1):match("[%w%p]") and not before:sub(-1):match("[%(%[{\"'`/.:@#$-]") and text:sub(1, 1):match("%w") then
    text = " " .. text
  end
  return text
end

local function request_one(gen, i, key, before, after, ft)
  local len = M.config.lengths[i]
  local body = vim.json.encode({
    model = M.config.model,
    temperature = M.config.temperature,
    max_tokens = len.max_tokens,
    messages = {
      { role = "system", content = M.config.system_prompt .. " Filetype: " .. (ft ~= "" and ft or "plain text") .. ". " .. len.instruction },
      { role = "user", content = "<text_before_cursor>\n" .. before .. "\n</text_before_cursor>\n<text_after_cursor>\n" .. after .. "\n</text_after_cursor>" },
    },
  })
  local body_file = vim.fn.tempname()
  local f = io.open(body_file, "w"); if not f then return end
  f:write(body); f:close()
  local t0 = vim.uv.hrtime()
  -- The key goes in via a curl config on stdin, so it is never in argv or on disk.
  local cmd = { "curl", "-sS", "--max-time", tostring(M.config.timeout_s), "-K", "-",
    "-H", "Content-Type: application/json", "-H", "HTTP-Referer: nvim-autocomplete", "-H", "X-Title: nvim autocomplete",
    "-d", "@" .. body_file, M.config.url }
  vim.system(cmd, { stdin = 'header = "Authorization: Bearer ' .. key .. '"\n', text = true }, function(res)
    vim.schedule(function()
      pcall(os.remove, body_file)
      if gen ~= S.gen then return end -- stale
      S.pending = S.pending - 1
      local ms = math.floor((vim.uv.hrtime() - t0) / 1e6)
      local text, err
      if res.code ~= 0 then
        if res.code == 6 or res.code == 7 then err = "offline (no connection to openrouter.ai)"
        elseif res.code == 28 then err = "timed out after " .. M.config.timeout_s .. "s"
        else err = "curl exit " .. res.code .. " " .. ((res.stderr or ""):match("[^\n]*") or "") end
      else
        local ok, data = pcall(vim.json.decode, res.stdout or "")
        if not ok or type(data) ~= "table" then err = "unreadable reply"
        elseif data.error then err = (data.error.message or "API error"):sub(1, 160)
        else
          local ch = data.choices and data.choices[1]
          text = ch and ch.message and ch.message.content
          if type(text) ~= "string" then err = "empty reply" end
        end
      end
      log({ event = "reply", model = M.config.model, length = len.name, ms = ms, ok = err == nil, err = err })
      if err then
        if not S.warned then S.warned = true; warn(err) end
        if S.pending == 0 and not S.idx then clear() end
        return
      end
      text = tidy(text, before)
      if text then
        S.candidates[i] = text
        if not S.idx then
          M.show(i)
        elseif i == M.config.default_length and S.candidates[S.idx] == nil then
          M.show(i)
        else
          echo(status_line())
        end
      elseif S.pending == 0 and not S.idx then
        echo("AI: nothing to add here")
      end
    end)
  end)
end

function M.trigger()
  if vim.fn.mode() ~= "i" then return end
  local key = get_key()
  if not key then
    warn("no API key: export OPENROUTER_API_KEY or `pass insert api/openrouter`")
    return
  end
  clear()
  pcall(function() require("blink.cmp").hide() end)
  S.buf = vim.api.nvim_get_current_buf()
  local pos = vim.api.nvim_win_get_cursor(0)
  S.row, S.col = pos[1] - 1, pos[2]
  S.warned = false
  S.pending = #M.config.lengths
  local gen = S.gen
  local before, after = context_text(S.buf, S.row, S.col)
  local ft = vim.bo[S.buf].filetype
  echo("AI: asking " .. M.config.model .. " …")
  for i = 1, #M.config.lengths do
    request_one(gen, i, key, before, after, ft)
  end
end

---------------------------------------------------------------------------
-- Model picker
---------------------------------------------------------------------------
local function fmt_price(p)
  local n = tonumber(p)
  if not n then return "?" end
  return string.format("%.2f", n * 1e6)
end

function M.browse_models()
  local key = get_key()
  echo("AI: fetching model list …")
  local cmd = { "curl", "-sS", "--max-time", "20", M.config.models_url }
  if key then table.insert(cmd, #cmd, "-H"); table.insert(cmd, #cmd, "Authorization: Bearer " .. key) end
  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      local ok, data = pcall(vim.json.decode, res.stdout or "")
      if res.code ~= 0 or not ok or type(data) ~= "table" or not data.data then
        warn("could not fetch the model list" .. (res.code ~= 0 and " (offline?)" or ""))
        return
      end
      local items = {}
      for _, m in ipairs(data.data) do
        local pr = m.pricing or {}
        items[#items + 1] = { id = m.id, label = string.format("%-50s in %6s  out %6s  ctx %s",
          m.id, fmt_price(pr.prompt), fmt_price(pr.completion), tostring(m.context_length or "?")) }
      end
      table.sort(items, function(a, b) return a.id < b.id end)
      echo("")
      vim.ui.select(items, {
        prompt = "OpenRouter model (" .. #items .. ", USD per 1M tokens)",
        format_item = function(it) return it.label end,
      }, function(choice)
        if choice then M.set_model(choice.id) end
      end)
    end)
  end)
end

function M.pick_model()
  local items = { { id = nil, label = "Browse all OpenRouter models …" } }
  for _, m in ipairs(M.config.models) do
    local cur = (m.id == M.config.model) and "● " or "  "
    items[#items + 1] = { id = m.id, label = string.format("%s%-36s %s", cur, m.id, m.note or "") }
  end
  -- Opening a picker leaves insert mode; remember where we were so a pick can resume and re-ask.
  local resume
  if vim.fn.mode() == "i" then
    local pos = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    resume = function()
      if pos[2] >= #line then vim.cmd("startinsert!")
      else vim.api.nvim_win_set_cursor(0, pos); vim.cmd("startinsert") end
      vim.schedule(M.trigger)
    end
  end
  vim.ui.select(items, {
    prompt = "AI autocomplete model (current: " .. M.config.model .. ")",
    format_item = function(it) return it.label end,
  }, function(choice)
    if not choice then return end
    if choice.id then
      M.set_model(choice.id)
      if resume then vim.schedule(resume) end
    else
      M.browse_models()
    end
  end)
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  load_model()
  local km = M.config.keymaps

  vim.keymap.set("i", km.trigger, M.trigger, { desc = "AI autocomplete: suggest", silent = true })
  vim.keymap.set("n", km.model_normal, M.pick_model, { desc = "AI autocomplete: pick model" })

  -- LazyVim routes <Tab> through its "ai_accept" action (works with blink.cmp's own Tab mapping).
  if _G.LazyVim and LazyVim.cmp and LazyVim.cmp.actions then
    M._lazyvim_tab = true
    LazyVim.cmp.actions.ai_accept = function()
      if S.idx and S.candidates[S.idx] then return M.accept() end
    end
  end

  local group = vim.api.nvim_create_augroup("ai_autocomplete", { clear = true })
  vim.api.nvim_create_autocmd({ "TextChangedI", "InsertLeave", "BufLeave" }, {
    group = group,
    callback = function()
      if S.accepting then return end
      if S.idx or S.pending > 0 then clear() end
    end,
  })
  vim.api.nvim_create_autocmd("CursorMovedI", {
    group = group,
    callback = function()
      if S.accepting or not S.idx then return end
      local pos = vim.api.nvim_win_get_cursor(0)
      if pos[1] - 1 ~= S.row or pos[2] ~= S.col then clear() end
    end,
  })

  vim.api.nvim_create_user_command("AiComplete", function() vim.cmd("startinsert"); vim.schedule(M.trigger) end, {})
  vim.api.nvim_create_user_command("AiModel", M.pick_model, {})
  vim.api.nvim_create_user_command("AiModelBrowse", M.browse_models, {})
  vim.api.nvim_create_user_command("AiLog", function() vim.cmd("edit " .. M.config.log_file) end, {})
end

-- exposed for tests
M._state = S
M._tidy = tidy

return M
