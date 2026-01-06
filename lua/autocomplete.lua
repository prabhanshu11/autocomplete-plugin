local M = {}

-- Configuration
M.config = {
  api_key = os.getenv("OPENROUTER_API_KEY") or "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",
  model = "google/gemini-3-flash-preview",  -- Default to Gemini 3 Flash
  thinking_enabled = false,
  max_tokens = 200,
  temperature = 0.3,
  db_path = vim.fn.stdpath("data") .. "/autocomplete.db",
  system_prompt_file = vim.fn.expand("~/autocomplete-plugin/SYSTEM_PROMPT.md"),
  auto_trigger = true,
  auto_trigger_delay = 2000,
}

-- Timer for auto-trigger
M.timer = nil

-- Current completion state
M.current_completion = nil
M.current_request_id = nil

-- Track last auto-trigger context to avoid re-triggering at same position
M.last_trigger_context = nil

-- Pending API results (for frontloading)
M.pending_result = nil
M.pending_timer = nil

-- Track completion position to detect stale completions
M.completion_position = nil

-- Initialize SQLite database
local function init_db()
  local db_path = M.config.db_path

  -- Create database and tables if they don't exist
  local init_sql = string.format([[
sqlite3 "%s" << 'EOF'
CREATE TABLE IF NOT EXISTS completions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_id TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  model TEXT NOT NULL,
  prompt_before TEXT NOT NULL,
  prompt_after TEXT NOT NULL,
  completion TEXT NOT NULL,
  prompt_tokens INTEGER,
  completion_tokens INTEGER,
  total_tokens INTEGER,
  cost REAL,
  response_time_ms INTEGER,
  accepted INTEGER DEFAULT 0,
  liked INTEGER DEFAULT NULL,
  filetype TEXT,
  reviewed_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_model ON completions(model);
CREATE INDEX IF NOT EXISTS idx_timestamp ON completions(timestamp);
CREATE INDEX IF NOT EXISTS idx_accepted ON completions(accepted);
CREATE INDEX IF NOT EXISTS idx_liked ON completions(liked);
EOF
]], db_path)

  os.execute(init_sql)
end

-- Log completion to database
local function log_completion(data)
  local db_path = M.config.db_path

  local sql = string.format([[
sqlite3 "%s" << 'EOF'
INSERT INTO completions (
  request_id, timestamp, model, prompt_before, prompt_after,
  completion, prompt_tokens, completion_tokens, total_tokens,
  cost, response_time_ms, filetype
) VALUES (
  '%s', '%s', '%s', '%s', '%s',
  '%s', %d, %d, %d,
  %f, %d, '%s'
);
EOF
]],
    db_path,
    data.request_id:gsub("'", "''"),
    os.date("%Y-%m-%d %H:%M:%S"),
    data.model:gsub("'", "''"),
    data.prompt_before:gsub("'", "''"):gsub("\n", "\\n"),
    data.prompt_after:gsub("'", "''"):gsub("\n", "\\n"),
    data.completion:gsub("'", "''"):gsub("\n", "\\n"),
    data.prompt_tokens or 0,
    data.completion_tokens or 0,
    data.total_tokens or 0,
    data.cost or 0,
    data.response_time_ms or 0,
    data.filetype:gsub("'", "''")
  )

  vim.fn.jobstart({"bash", "-c", sql}, {detach = true})
end

-- Update completion review
local function update_review(request_id, accepted, liked)
  local db_path = M.config.db_path

  local liked_value = "NULL"
  if liked ~= nil then
    liked_value = liked and "1" or "0"
  end

  local sql = string.format([[
sqlite3 "%s" "UPDATE completions SET accepted = %d, liked = %s, reviewed_at = '%s' WHERE request_id = '%s';"
]],
    db_path,
    accepted and 1 or 0,
    liked_value,
    os.date("%Y-%m-%d %H:%M:%S"),
    request_id:gsub("'", "''")
  )

  vim.fn.jobstart({"bash", "-c", sql}, {detach = true})
end

-- Toggle thinking mode
function M.toggle_thinking()
  M.config.thinking_enabled = not M.config.thinking_enabled
  local status = M.config.thinking_enabled and "ON" or "OFF"
  vim.notify("Extended Thinking: " .. status, vim.log.levels.INFO)
end

-- Get context from current buffer
local function get_context()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  local col = cursor[2]

  -- Get all lines
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  -- Get before and after cursor
  local before_cursor = table.concat(vim.list_slice(lines, 1, row - 1), "\n")
  if row > 0 then
    before_cursor = before_cursor .. "\n" .. string.sub(lines[row], 1, col)
  end

  local after_cursor = ""
  if row <= #lines then
    after_cursor = string.sub(lines[row], col + 1) .. "\n"
    if row < #lines then
      after_cursor = after_cursor .. table.concat(vim.list_slice(lines, row + 1, #lines), "\n")
    end
  end

  return before_cursor, after_cursor
end

-- Clear virtual text completion preview
local function clear_preview()
  if M.current_completion and M.current_completion.ns_id then
    vim.api.nvim_buf_clear_namespace(0, M.current_completion.ns_id, 0, -1)
  end
  if M.current_completion and M.current_completion.keymaps_set then
    -- Remove temporary keymaps
    pcall(vim.keymap.del, 'i', '<Tab>', { buffer = 0 })
    pcall(vim.keymap.del, 'i', '<Esc>', { buffer = 0 })
    pcall(vim.keymap.del, 'i', '<C-r>', { buffer = 0 })
    pcall(vim.keymap.del, 'i', '<C-l>', { buffer = 0 })
    pcall(vim.keymap.del, 'i', '<C-d>', { buffer = 0 })
  end
  M.current_completion = nil

  -- Clear pending results and timers
  M.pending_result = nil
  if M.pending_timer then
    M.pending_timer:stop()
    M.pending_timer = nil
  end

  -- Reset last trigger context so it can trigger again after changes
  M.last_trigger_context = nil
  M.completion_position = nil
end

-- Check if completion is stale (cursor moved)
local function is_completion_stale()
  if not M.current_completion or not M.completion_position then
    return false
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  -- Stale if cursor row or column changed
  return cursor[1] ~= M.completion_position.row or cursor[2] ~= M.completion_position.col
end

-- Accept completion
function M.accept_completion()
  if not M.current_completion then
    return
  end

  local completion = M.current_completion.text
  local request_id = M.current_completion.request_id

  -- Clear preview
  clear_preview()

  -- Insert completion at cursor
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  -- Split completion into lines
  local lines = vim.split(completion, "\n", { plain = true })

  -- Insert the completion
  vim.api.nvim_buf_set_text(0, row, col, row, col, lines)

  -- Move cursor to end of insertion
  if #lines > 1 then
    vim.api.nvim_win_set_cursor(0, {row + #lines, #lines[#lines]})
  else
    vim.api.nvim_win_set_cursor(0, {row + 1, col + #lines[1]})
  end

  -- Log acceptance
  update_review(request_id, true, nil)

  vim.notify("Completion accepted", vim.log.levels.INFO)
end

-- Reject completion and request new one
function M.reject_completion()
  if not M.current_completion then
    return
  end

  local request_id = M.current_completion.request_id

  -- Log rejection
  update_review(request_id, false, nil)

  -- Clear and get new completion
  clear_preview()
  vim.notify("Rejected. Getting new completion...", vim.log.levels.INFO)
  M.autocomplete()
end

-- Like completion
function M.like_completion()
  if not M.current_completion then
    return
  end

  local request_id = M.current_completion.request_id
  update_review(request_id, M.current_completion.accepted or false, true)

  vim.notify("👍 Liked", vim.log.levels.INFO)
end

-- Dislike completion
function M.dislike_completion()
  if not M.current_completion then
    return
  end

  local request_id = M.current_completion.request_id
  update_review(request_id, M.current_completion.accepted or false, false)

  vim.notify("👎 Disliked", vim.log.levels.INFO)
end

-- Dismiss completion
function M.dismiss_completion()
  if not M.current_completion then
    return
  end

  local request_id = M.current_completion.request_id
  update_review(request_id, false, nil)

  clear_preview()
  vim.notify("Completion dismissed", vim.log.levels.INFO)
end

-- Wrap text to fit window width
local function wrap_text(text, max_width, first_line_offset)
  first_line_offset = first_line_offset or 0
  local wrapped_lines = {}

  -- Split by newlines first
  local lines = vim.split(text, "\n", { plain = true })

  for line_idx, line in ipairs(lines) do
    local available_width = max_width
    -- First line has reduced width due to cursor position
    if line_idx == 1 then
      available_width = max_width - first_line_offset
    end

    -- If line fits, add it directly
    if #line <= available_width then
      table.insert(wrapped_lines, line)
    else
      -- Wrap long line into multiple lines
      local remaining = line
      local first_chunk = true

      while #remaining > 0 do
        local chunk_width = first_chunk and available_width or max_width

        if #remaining <= chunk_width then
          table.insert(wrapped_lines, remaining)
          break
        end

        -- Try to break at word boundary
        local chunk = string.sub(remaining, 1, chunk_width)
        local last_space = chunk:match("^.*()%s")

        if last_space and last_space > chunk_width * 0.5 then
          -- Break at word boundary
          table.insert(wrapped_lines, string.sub(remaining, 1, last_space - 1))
          remaining = string.sub(remaining, last_space + 1)
        else
          -- Hard break
          table.insert(wrapped_lines, chunk)
          remaining = string.sub(remaining, chunk_width + 1)
        end

        first_chunk = false
      end
    end
  end

  return wrapped_lines
end

-- Show completion preview with virtual text
local function show_preview(completion_text)
  -- Hide blink.cmp ghost text and menu to avoid overlap
  pcall(function() require('blink.cmp').hide() end)

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]

  -- Get window width for wrapping
  local win_width = vim.api.nvim_win_get_width(0)
  -- Account for line numbers, sign column, etc.
  local textoff = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].textoff
  local available_width = win_width - textoff - 2 -- -2 for safety margin

  -- Create namespace for virtual text
  local ns_id = vim.api.nvim_create_namespace('autocomplete_preview')

  -- Wrap text to window width
  local wrapped_lines = wrap_text(completion_text, available_width, col)

  -- Show first line as virtual text on current line
  if #wrapped_lines > 0 then
    -- Prepare options for extmark
    local extmark_opts = {
      virt_text = {{wrapped_lines[1], "Comment"}},
      virt_text_pos = "overlay",
      priority = 1000, -- High priority to ensure it shows over other text
    }

    -- If there are continuation lines, add them as virt_lines
    if #wrapped_lines > 1 then
      local continuation_lines = {}
      for i = 2, #wrapped_lines do
        table.insert(continuation_lines, {{wrapped_lines[i], "Comment"}})
      end
      extmark_opts.virt_lines = continuation_lines
      extmark_opts.virt_lines_above = false
    end

    -- Set single extmark with all the virtual text
    vim.api.nvim_buf_set_extmark(0, ns_id, row, col, extmark_opts)
  end

  -- Track completion position for staleness detection
  M.completion_position = { row = cursor[1], col = cursor[2] }

  return ns_id
end

-- Load system prompt from file
local function load_system_prompt()
  local default_prompt = [[Act like an intelligent autocomplete. You will receive code with a cursor position marked by <CURSOR>. Your job is to predict what the user wants to type next. Output ONLY the completion text - no explanations, no markdown, no additional commentary. Be concise and contextual. Complete the current thought, statement, or logical block.]]

  local prompt_file = M.config.system_prompt_file
  if not prompt_file or not vim.fn.filereadable(prompt_file) == 1 then
    return default_prompt
  end

  -- Read the file
  local file = io.open(vim.fn.expand(prompt_file), "r")
  if not file then
    return default_prompt
  end

  local content = file:read("*all")
  file:close()

  -- Extract prompt from markdown code block
  local prompt = content:match("```\n(.-)\n```")
  if prompt and prompt ~= "" then
    return prompt
  end

  return default_prompt
end

-- Call OpenRouter API
local function call_api(prompt_before, prompt_after, callback)
  local curl = require('plenary.curl')
  local start_time = vim.loop.hrtime()

  local system_prompt = load_system_prompt()
  local prompt = prompt_before .. "<CURSOR>" .. prompt_after

  local messages = {
    {
      role = "system",
      content = system_prompt
    },
    {
      role = "user",
      content = prompt
    }
  }

  local body = {
    model = M.config.model,
    max_tokens = M.config.max_tokens,
    temperature = M.config.temperature,
    messages = messages,
  }

  -- OpenRouter extended thinking for Claude models (if enabled)
  if M.config.thinking_enabled and string.match(M.config.model, "claude") then
    body.thinking = {
      type = "enabled",
      budget_tokens = 1000
    }
  end

  curl.post('https://openrouter.ai/api/v1/chat/completions', {
    headers = {
      ['Content-Type'] = 'application/json',
      ['Authorization'] = 'Bearer ' .. M.config.api_key,
      ['HTTP-Referer'] = 'https://github.com/autocomplete-plugin',
      ['X-Title'] = 'Neovim Autocomplete',
    },
    body = vim.json.encode(body),
    callback = vim.schedule_wrap(function(response)
      local response_time_ms = math.floor((vim.loop.hrtime() - start_time) / 1000000)

      if response.status ~= 200 then
        if response.status == 401 then
          vim.notify(
            "API key invalid or disabled. Check: https://openrouter.ai/keys",
            vim.log.levels.ERROR
          )
        else
          vim.notify("OpenRouter API Error: " .. (response.body or "Unknown error"), vim.log.levels.ERROR)
        end
        return
      end

      local ok, data = pcall(vim.json.decode, response.body)
      if not ok then
        vim.notify("Failed to parse API response", vim.log.levels.ERROR)
        return
      end

      -- Extract text from OpenAI-compatible response
      local completion = ""
      if data.choices and data.choices[1] and data.choices[1].message then
        completion = data.choices[1].message.content or ""
      end

      -- Extract usage and cost info
      local usage = data.usage or {}

      callback({
        completion = completion,
        prompt_tokens = usage.prompt_tokens or 0,
        completion_tokens = usage.completion_tokens or 0,
        total_tokens = usage.total_tokens or 0,
        cost = usage.cost or 0,
        response_time_ms = response_time_ms,
      })
    end),
  })
end

-- Frontload API call (call immediately, show later)
local function autocomplete_frontload()
  if M.config.api_key == "" then
    return
  end

  -- Only make API call if in insert mode
  local mode = vim.api.nvim_get_mode().mode
  if mode ~= 'i' then
    return
  end

  local before, after = get_context()
  local filetype = vim.bo.filetype or "unknown"
  local cursor = vim.api.nvim_win_get_cursor(0)
  local context_snapshot = string.format("%d:%d:%s:%s", cursor[1], cursor[2], before, after)

  -- Make API call immediately (in background)
  call_api(before, after, function(result)
    if result.completion and result.completion ~= "" then
      -- Store result for later display
      M.pending_result = {
        result = result,
        before = before,
        after = after,
        filetype = filetype,
        context = context_snapshot,
      }
    end
  end)
end

-- Show pending result (called after delay)
local function show_pending_result()
  if not M.pending_result then
    return
  end

  local pending = M.pending_result
  M.pending_result = nil

  -- Verify context hasn't changed
  local cursor = vim.api.nvim_win_get_cursor(0)
  local before, after = get_context()
  local current_context = string.format("%d:%d:%s:%s", cursor[1], cursor[2], before, after)

  if current_context ~= pending.context then
    -- Context changed, don't show stale result
    return
  end

  -- Generate unique request ID
  local request_id = string.format("%s_%d", M.config.model:gsub("/", "_"), os.time())

  -- Log to database
  log_completion({
    request_id = request_id,
    model = M.config.model,
    prompt_before = pending.before,
    prompt_after = pending.after,
    completion = pending.result.completion,
    prompt_tokens = pending.result.prompt_tokens,
    completion_tokens = pending.result.completion_tokens,
    total_tokens = pending.result.total_tokens,
    cost = pending.result.cost,
    response_time_ms = pending.result.response_time_ms,
    filetype = pending.filetype,
  })

  -- Show preview
  local ns_id = show_preview(pending.result.completion)

  -- Store current completion
  M.current_completion = {
    text = pending.result.completion,
    request_id = request_id,
    ns_id = ns_id,
    accepted = false,
    keymaps_set = false,
  }

  -- Set up temporary keymaps
  vim.keymap.set('i', '<Tab>', function()
    M.accept_completion()
  end, { buffer = true, desc = "Accept completion" })

  vim.keymap.set('i', '<C-r>', function()
    M.reject_completion()
  end, { buffer = true, desc = "Reject and refresh completion" })

  vim.keymap.set('i', '<C-l>', function()
    M.like_completion()
  end, { buffer = true, desc = "Like completion" })

  vim.keymap.set('i', '<C-d>', function()
    M.dislike_completion()
  end, { buffer = true, desc = "Dislike completion" })

  vim.keymap.set('i', '<Esc>', function()
    M.dismiss_completion()
  end, { buffer = true, desc = "Dismiss completion" })

  M.current_completion.keymaps_set = true

  vim.notify("Tab: accept | Ctrl+R: refresh | Ctrl+L: like | Ctrl+D: dislike", vim.log.levels.INFO)
end

-- Trigger autocomplete (for manual triggering)
function M.autocomplete(opts)
  opts = opts or {}
  if M.config.api_key == "" then
    vim.notify("OPENROUTER_API_KEY not set", vim.log.levels.ERROR)
    return
  end

  -- Clear any existing preview
  clear_preview()

  local before, after = get_context()
  local filetype = vim.bo.filetype or "unknown"

  if not opts.silent then
    vim.notify("Getting completion...", vim.log.levels.INFO)
  end

  call_api(before, after, function(result)
    if result.completion and result.completion ~= "" then
      -- Generate unique request ID
      local request_id = string.format("%s_%d", M.config.model:gsub("/", "_"), os.time())

      -- Log to database
      log_completion({
        request_id = request_id,
        model = M.config.model,
        prompt_before = before,
        prompt_after = after,
        completion = result.completion,
        prompt_tokens = result.prompt_tokens,
        completion_tokens = result.completion_tokens,
        total_tokens = result.total_tokens,
        cost = result.cost,
        response_time_ms = result.response_time_ms,
        filetype = filetype,
      })

      -- Show preview
      local ns_id = show_preview(result.completion)

      -- Store current completion
      M.current_completion = {
        text = result.completion,
        request_id = request_id,
        ns_id = ns_id,
        accepted = false,
        keymaps_set = false,
      }

      -- Set up temporary keymaps for this completion
      vim.keymap.set('i', '<Tab>', function()
        M.accept_completion()
      end, { buffer = true, desc = "Accept completion" })

      vim.keymap.set('i', '<C-r>', function()
        M.reject_completion()
      end, { buffer = true, desc = "Reject and refresh completion" })

      vim.keymap.set('i', '<C-l>', function()
        M.like_completion()
      end, { buffer = true, desc = "Like completion" })

      vim.keymap.set('i', '<C-d>', function()
        M.dislike_completion()
      end, { buffer = true, desc = "Dislike completion" })

      vim.keymap.set('i', '<Esc>', function()
        M.dismiss_completion()
      end, { buffer = true, desc = "Dismiss completion" })

      M.current_completion.keymaps_set = true

      vim.notify("Tab: accept | Ctrl+R: refresh | Ctrl+L: like | Ctrl+D: dislike", vim.log.levels.INFO)
    end
  end)
end

-- Setup function
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)

  -- Initialize database
  init_db()

  -- Set up auto-dismiss when leaving insert mode
  local dismiss_group = vim.api.nvim_create_augroup("AutocompleteDismiss", { clear = true })
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = dismiss_group,
    callback = function()
      -- Auto-dismiss completion when leaving insert mode
      if M.current_completion then
        clear_preview()
      end
    end,
  })

  -- Set up auto-trigger if enabled
  if M.config.auto_trigger then
    local group = vim.api.nvim_create_augroup("AutocompleteAutoTrigger", { clear = true })
    vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
      group = group,
      callback = function()
        -- Check if current completion is stale (cursor moved)
        if M.current_completion then
          if is_completion_stale() then
            clear_preview()
          else
            return
          end
        end

        -- Get current context
        local cursor = vim.api.nvim_win_get_cursor(0)
        local before, after = get_context()
        local current_context = string.format("%d:%d:%s:%s", cursor[1], cursor[2], before, after)

        -- Only proceed if context changed since last trigger
        if current_context == M.last_trigger_context then
          return
        end

        M.last_trigger_context = current_context

        -- Cancel any pending display timers
        if M.pending_timer then
          M.pending_timer:stop()
          M.pending_timer = nil
        end

        -- Clear any stale pending results
        M.pending_result = nil

        -- Start API call immediately (frontload)
        autocomplete_frontload()

        -- Set timer to show result after delay
        M.pending_timer = vim.defer_fn(function()
          -- Only show if still in insert mode and no completion is active
          local mode = vim.api.nvim_get_mode().mode
          if mode == 'i' and not M.current_completion then
            show_pending_result()
          end
          M.pending_timer = nil
        end, M.config.auto_trigger_delay)
      end,
    })
  end

  -- Create commands
  vim.api.nvim_create_user_command('ClaudeComplete', M.autocomplete, {})
  vim.api.nvim_create_user_command('ClaudeToggleThinking', M.toggle_thinking, {})
  vim.api.nvim_create_user_command('ClaudeAccept', M.accept_completion, {})
  vim.api.nvim_create_user_command('ClaudeReject', M.reject_completion, {})
  vim.api.nvim_create_user_command('ClaudeLike', M.like_completion, {})
  vim.api.nvim_create_user_command('ClaudeDislike', M.dislike_completion, {})

  -- Set up keymaps if provided
  if opts.keymaps then
    if opts.keymaps.complete then
      vim.keymap.set('i', opts.keymaps.complete, function()
        M.autocomplete()
      end, { desc = "Trigger autocomplete" })
    end

    if opts.keymaps.toggle_thinking then
      vim.keymap.set('n', opts.keymaps.toggle_thinking, function()
        M.toggle_thinking()
      end, { desc = "Toggle thinking mode" })
    end
  end

  vim.notify("Autocomplete plugin loaded. DB: " .. M.config.db_path, vim.log.levels.INFO)
end

return M
