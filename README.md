# AI Autocomplete for Neovim with Analytics

Intelligent autocomplete powered by any LLM model via OpenRouter, with built-in quality tracking and analytics.

## Features

✨ **Smart Completion Preview** - See suggestions before accepting
⚡ **Multi-Model Support** - Test Gemini, Claude, DeepSeek, Kimi, and more
📊 **Quality Tracking** - Like/dislike completions to track model performance
💾 **SQLite Analytics** - All predictions stored with cost and timing data
🐍 **Python Reports** - Generate detailed model comparison reports
🎯 **Quality Scores** - Calculated from acceptance rate, likes, and dislikes (0-1 scale)

## Prerequisites

- Neovim 0.8+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- OpenRouter API key from [openrouter.ai](https://openrouter.ai)
- SQLite3 (for analytics database)
- Python 3 (for generating reports)

## Installation

### 1. Get API Key

Sign up at [openrouter.ai](https://openrouter.ai) and get your API key:

```bash
export OPENROUTER_API_KEY="your-api-key-here"
```

Add to `.bashrc`/`.zshrc` to persist.

### 2. Install Plugin

**Using lazy.nvim:**

```lua
{
  dir = vim.fn.expand("~/autocomplete-plugin"),
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("autocomplete").setup({
      model = "google/gemini-3-flash-preview",  -- Default model
      keymaps = {
        complete = "<C-a>",           -- Trigger autocomplete
        toggle_thinking = "<leader>ct", -- Toggle extended thinking
      },
    })
  end,
}
```

**Using packer.nvim:**

```lua
use {
  "~/autocomplete-plugin",
  requires = { "nvim-lua/plenary.nvim" },
  config = function()
    require("autocomplete").setup({
      model = "google/gemini-3-flash-preview",
      keymaps = {
        complete = "<C-a>",
        toggle_thinking = "<leader>ct",
      },
    })
  end,
}
```

## Usage

### Workflow

1. **Trigger completion:** Press `Ctrl+A` (or your configured key) in insert mode
2. **Preview appears:** Completion shows as grayed-out virtual text
3. **Review and act:**
   - **Tab** - Accept and insert completion
   - **Ctrl+R** - Reject and get new suggestion
   - **Ctrl+L** - Like this completion (positive feedback)
   - **Ctrl+D** - Dislike this completion (negative feedback)
   - **Esc** - Dismiss without action

### Example Session

```javascript
// You type:
function multiply(x, y) {
  // [Press Ctrl+A]

// Completion appears in gray:
  return x * y;

// Press Tab to accept, or Ctrl+R for different suggestion
```

### Commands

- `:ClaudeComplete` - Trigger completion
- `:ClaudeAccept` - Accept current completion
- `:ClaudeReject` - Reject and refresh
- `:ClaudeLike` - Like completion
- `:ClaudeDislike` - Dislike completion
- `:ClaudeToggleThinking` - Toggle extended thinking mode

## Analytics & Tracking

All completions are automatically logged to SQLite database at:
```
~/.local/share/nvim/autocomplete.db
```

Tracked data includes:
- Model used
- Prompt context (before/after cursor)
- Completion text
- Token usage and cost
- Response time
- Acceptance (Tab pressed)
- Like/Dislike feedback
- File type
- Timestamp

## Customizing System Prompt

Edit `SYSTEM_PROMPT.md` to customize how the AI completes your code:

```bash
# Edit the prompt
nano ~/autocomplete-plugin/SYSTEM_PROMPT.md

# The plugin automatically reads from this file
# Restart Neovim to apply changes
```

The prompt is extracted from the markdown code block. Change it to match your preferences (verbose/minimal, language-specific, style guide, etc.).

## Generating Reports

Run the Python analysis scripts to generate detailed reports:

```bash
cd ~/autocomplete-plugin

# Generate model statistics and quality scores
python3 analyze.py

# Append real completion examples with likes/dislikes
python3 generate_examples.py
```

**analyze.py** generates `MODEL_COMPARISON.md` with:
- Quality scores for each model (0-1 scale)
- Cost analysis per completion
- Projected costs for 10,000 completions
- Acceptance rates
- Like/dislike ratios
- Response time averages
- Recommendations

**generate_examples.py** appends real examples with feedback:
- 👍 Liked completions (positive examples)
- 👎 Disliked completions (what didn't work)
- Context, completion, cost, and timing for each
- Up to 20 most recent reviewed completions

### Quality Score Formula

Quality score (0-1) is calculated as:
- **40%** Acceptance rate (Tab pressed / Total)
- **40%** Like rate (Likes / Total reviewed)
- **20%** Inverse dislike rate (1 - Dislikes / Total reviewed)

Higher score = Better user satisfaction

## Configuration

```lua
require("autocomplete").setup({
  api_key = nil,  -- Defaults to OPENROUTER_API_KEY env var
  model = "google/gemini-3-flash-preview",
  thinking_enabled = false,
  max_tokens = 200,
  temperature = 0.3,
  db_path = vim.fn.stdpath("data") .. "/autocomplete.db",
  keymaps = {
    complete = "<C-a>",
    toggle_thinking = "<leader>ct",
  },
})
```

## Recommended Models

Based on initial testing (see `MODEL_COMPARISON.md`):

| Model | Cost/Completion | Quality | Use Case |
|-------|-----------------|---------|----------|
| `deepseek/deepseek-chat` | $0.000016 | Good | Best budget option |
| `google/gemini-3-flash-preview` | $0.000031 | Excellent | **Recommended default** |
| `google/gemini-2.5-flash` | $0.000022 | Excellent | Great balance |
| `moonshotai/kimi-k2` | $0.000040 | Good | Alternative option |
| `anthropic/claude-3.5-haiku` | $0.000065 | Excellent | Premium quality |

Change model in your config:

```lua
require("autocomplete").setup({
  model = "deepseek/deepseek-chat",  -- Switch to cheaper model
  -- ...
})
```

Browse all models: [openrouter.ai/models](https://openrouter.ai/models)

## Testing Multiple Models

Want to compare models? Try each for a day and review the analytics:

**Day 1:** Use Gemini 3 Flash
**Day 2:** Use DeepSeek Chat
**Day 3:** Use Claude Haiku

Then run `python3 analyze.py` to see which performs best for your workflow!

## Database Schema

```sql
CREATE TABLE completions (
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
  liked INTEGER DEFAULT NULL,  -- 1=liked, 0=disliked, NULL=not reviewed
  filetype TEXT,
  reviewed_at TEXT
);
```

Query your own data:

```bash
sqlite3 ~/.local/share/nvim/autocomplete.db "SELECT model, COUNT(*), AVG(cost) FROM completions GROUP BY model;"
```

## Troubleshooting

**"OPENROUTER_API_KEY not set"**
- Export the key and restart Neovim

**Completion doesn't appear**
- Check `:messages` for errors
- Ensure plenary.nvim is installed
- Try `:ClaudeComplete` command

**Virtual text hard to see**
- Adjust your theme's `Comment` highlight group
- Or modify `show_preview()` function to use different highlight

**Database too large**
- Delete old entries: `sqlite3 ~/.local/share/nvim/autocomplete.db "DELETE FROM completions WHERE timestamp < date('now', '-30 days');"`

**Python script fails**
- Install Python 3: `sudo apt install python3`
- Check database exists: `ls ~/.local/share/nvim/autocomplete.db`

## Testing Recent Fixes

The following issues were recently fixed and need testing to verify proper behavior:

### Test 1: API Key Error Handling (401 Errors)

**What was fixed:** Better error messages when API key is invalid or disabled.

**How to test:**
1. Temporarily set an invalid API key:
   ```bash
   export OPENROUTER_API_KEY="invalid-key-12345"
   ```
2. Restart Neovim
3. Trigger a completion with `Ctrl+A`

**Expected behavior:**
- Should show error: `"API key invalid or disabled. Check: https://openrouter.ai/keys"`
- Message should be clear and actionable (not raw JSON)

**To restore:**
```bash
export OPENROUTER_API_KEY="your-real-api-key"
```

### Test 2: Tab Key Restoration After Dismiss

**What was fixed:** Tab key now properly returns to normal behavior after dismissing completion with Escape.

**How to test:**
1. Trigger a completion with `Ctrl+A` (or wait for auto-trigger after 2 seconds of pause)
2. When completion appears (gray text), press `Esc` to dismiss
3. Immediately try pressing `Tab`

**Expected behavior:**
- `Tab` should insert spaces/tabs normally (not try to accept non-existent completion)
- Escape key should work to dismiss completions
- Tab should work normally in insert mode after dismissal

**Additional test:**
1. Trigger completion
2. Press `Tab` to accept it
3. Type more code
4. Press `Tab` again

**Expected:** Tab works normally after accepting completion too.

### Test 3: Stale Completion Clearing

**What was fixed:** Old completions now clear automatically when you continue typing.

**How to test:**
1. Type some code and stop for 2+ seconds (auto-trigger delay)
2. Wait for completion suggestion to appear (gray text)
3. **Without accepting or dismissing**, continue typing new characters

**Expected behavior:**
- Old completion should disappear immediately when you start typing
- After pausing again (2 seconds), a NEW completion should appear at the new cursor position
- Old suggestion should NOT persist while typing

**Example scenario:**
```javascript
// Step 1: Type "function delete" and stop
function delete
// Gray suggestion appears: "Record(id) { ... }"

// Step 2: Continue typing "RM" immediately
function deleteRM
// Expected: Old suggestion disappears, no ghost text visible

// Step 3: Stop typing for 2+ seconds
// Expected: NEW suggestion appears for "deleteRM..."
```

### Test 4: All Keymaps Working Together

**What was fixed:** All keymaps (Tab, Escape, Ctrl+R, Ctrl+L, Ctrl+D) now properly work and cleanup.

**How to test:**
1. Trigger completion with `Ctrl+A`
2. When suggestion appears, try each action:
   - Press `Ctrl+L` (like) - should show "👍 Liked"
   - Press `Ctrl+D` (dislike) - should show "👎 Disliked"
   - Press `Ctrl+R` (reject/refresh) - should get new completion
   - Press `Esc` (dismiss) - should clear and restore normal mode
   - Press `Tab` (accept) - should insert completion text

**Expected behavior:**
- All keymaps work correctly
- After any dismissal action, Tab/Esc return to normal behavior
- No "stuck" keymaps that persist after completion is gone

### Test 5: Auto-Trigger with Frontloading

**What to verify:** Auto-trigger still works correctly after the fixes.

**How to test:**
1. Open a file in Neovim
2. Type some code
3. Stop typing and wait 2 seconds
4. Completion should appear automatically

**Expected behavior:**
- After 2 seconds of no typing, completion appears
- API call happens in background (frontloading)
- No noticeable delay when completion displays

### Reporting Issues

If any test fails, please:
1. Note which test failed and what happened instead
2. Check `:messages` in Neovim for error details
3. Report the issue with steps to reproduce
4. Include your Neovim version (`:version`) and model being used

### Automated Testing (Future Work)

Currently all tests require manual interaction. Future improvements could include:
- Unit tests for helper functions (e.g., `is_completion_stale()`)
- Integration tests using Neovim headless mode
- Mock API responses to test error handling
- Automated keymap binding/unbinding tests

## Advanced: Custom Quality Metrics

Edit `analyze.py` to customize the quality score formula:

```python
def calculate_quality_score(accepted, liked, disliked, total):
    # Customize weights here
    score = (
        0.5 * acceptance_rate +  # More weight on acceptance
        0.3 * like_rate +
        0.2 * (1 - dislike_penalty)
    )
    return score
```

## Files

```
autocomplete-plugin/
├── lua/autocomplete.lua            # Main plugin (reads SYSTEM_PROMPT.md)
├── plugin/autocomplete.vim         # Vim loader
├── analyze.py                      # Generate model statistics
├── generate_examples.py            # Append real examples to report
├── SYSTEM_PROMPT.md                # Edit this to customize AI behavior
├── README.md                       # This file
├── QUICKSTART.md                   # Quick setup guide
├── MODEL_COMPARISON.md             # Main report (stats + examples)
├── MODEL_COMPARISON_GENERATED.md   # Notice file (Linux convention)
├── PROJECT_SUMMARY.md              # Project overview
├── example-config.lua              # Example configs
└── test_api.sh                     # API test script
```

### Two-File System (Linux Convention)

- **MODEL_COMPARISON.md** - Main report file (top = stats, bottom = examples)
- **MODEL_COMPARISON_GENERATED.md** - Notice file pointing to main file

This follows standard Linux practice where generated files reference the authoritative file.

## Contributing

Track issues or suggest improvements for this plugin. The database-driven approach makes it easy to experiment with quality metrics and model comparisons.

## License

MIT

---

**🔑 Remember:** This plugin tracks your API usage and costs. Run `python3 analyze.py` regularly to monitor spending and optimize model choice!
