# Complete Usage Guide

## Quick Reference

### Keybindings

| Key | Mode | Action |
|-----|------|--------|
| `Ctrl+A` | Insert | Trigger autocomplete |
| `Tab` | Insert* | Accept completion |
| `Ctrl+R` | Insert* | Reject and get new completion |
| `Ctrl+L` | Insert* | Like completion (positive feedback) |
| `Ctrl+D` | Insert* | Dislike completion (negative feedback) |
| `Esc` | Insert* | Dismiss completion |
| `<leader>ct` | Normal | Toggle extended thinking |

*Only active when completion preview is shown

### Commands

```vim
:ClaudeComplete          " Trigger completion manually
:ClaudeAccept           " Accept current completion
:ClaudeReject           " Reject and refresh
:ClaudeLike             " Mark as liked
:ClaudeDislike          " Mark as disliked
:ClaudeToggleThinking   " Toggle thinking mode
```

## Workflow Examples

### Example 1: Basic Usage

```javascript
// 1. Type your code
function calculateTax(amount, rate) {
  // 2. Press Ctrl+A here

// 3. See preview in gray text:
  return amount * rate;

// 4. Press Tab to accept, or Ctrl+R for different suggestion
```

### Example 2: Review and Improve

```python
# Type some code
def process_data(items):
    # Press Ctrl+A

# Preview appears:
    return [item.upper() for item in items]

# If you like it: Press Ctrl+L then Tab
# If you don't: Press Ctrl+D then Esc
# Want different: Press Ctrl+R
```

### Example 3: Switching Models

```lua
-- Try different models for comparison

-- Day 1: Gemini 3 Flash (default)
require("autocomplete").setup({
  model = "google/gemini-3-flash-preview",
  keymaps = { complete = "<C-a>", toggle_thinking = "<leader>ct>" },
})

-- Day 2: DeepSeek (cheapest)
require("autocomplete").setup({
  model = "deepseek/deepseek-chat",
  keymaps = { complete = "<C-a>", toggle_thinking = "<leader>ct>" },
})

-- Day 3: Claude (premium)
require("autocomplete").setup({
  model = "anthropic/claude-3.5-haiku",
  keymaps = { complete = "<C-a>", toggle_thinking = "<leader>ct>" },
})

-- Then run: python3 analyze.py
-- Compare which model you liked best!
```

## Customization

### Custom System Prompt

Edit `SYSTEM_PROMPT.md`:

```bash
nano ~/autocomplete-plugin/SYSTEM_PROMPT.md
```

Example prompts:

**Minimal (short completions):**
```
Complete the code with the shortest possible implementation. No comments.
```

**Detailed (verbose):**
```
Complete the code with full implementations including error handling, type hints, and inline comments.
```

**Language-specific (Python):**
```
Act as a Python autocomplete. Follow PEP 8. Use type hints. Prefer list comprehensions and context managers.
```

**Framework-specific (React):**
```
Complete React code using modern hooks (useState, useEffect, etc.). Follow React best practices. Use TypeScript types.
```

### Custom Keybindings

```lua
require("autocomplete").setup({
  keymaps = {
    complete = "<C-Space>",      -- Change Ctrl+A to Ctrl+Space
    toggle_thinking = "<leader>t", -- Change to leader+t
  },
})
```

### Database Location

```lua
require("autocomplete").setup({
  db_path = vim.fn.expand("~/my-autocomplete.db"),  -- Custom location
})
```

### Model Settings

```lua
require("autocomplete").setup({
  model = "google/gemini-3-flash-preview",
  max_tokens = 300,        -- Longer completions
  temperature = 0.5,       -- More creative (0-1, higher = more random)
  thinking_enabled = true, -- Always use thinking (Claude models only)
})
```

## Analytics Workflow

### Daily Usage

```bash
# 1. Use the plugin throughout the day
# Press Ctrl+A for completions
# Press Ctrl+L for good ones, Ctrl+D for bad ones

# 2. End of day: Check your stats
cd ~/autocomplete-plugin
python3 analyze.py

# 3. See examples with feedback
python3 generate_examples.py

# 4. Review MODEL_COMPARISON.md
cat MODEL_COMPARISON.md
```

### Weekly Review

```bash
# Generate full report
python3 analyze.py
python3 generate_examples.py

# Check costs
sqlite3 ~/.local/share/nvim/autocomplete.db \
  "SELECT model, COUNT(*), SUM(cost) FROM completions GROUP BY model;"

# Find best model
# Look at quality scores in MODEL_COMPARISON.md
# Switch to highest scoring model
```

### Monthly Cleanup

```bash
# Delete old completions (keep last 30 days)
sqlite3 ~/.local/share/nvim/autocomplete.db \
  "DELETE FROM completions WHERE timestamp < date('now', '-30 days');"

# Vacuum to reclaim space
sqlite3 ~/.local/share/nvim/autocomplete.db "VACUUM;"
```

## Troubleshooting

### Completion Doesn't Appear

```vim
" Check for errors
:messages

" Try manual command
:ClaudeComplete

" Check if plenary is installed
:lua require('plenary.curl')
```

### Can't See Virtual Text

The preview might blend with your background. Try:

```lua
-- Add to your Neovim config
vim.api.nvim_set_hl(0, 'Comment', { fg = '#606060', italic = true })
```

Or edit the plugin to use a different highlight group.

### Database Not Found

```bash
# Check if database exists
ls -lh ~/.local/share/nvim/autocomplete.db

# If not, the plugin will create it on first use
# Trigger a completion with Ctrl+A
```

### API Errors

```vim
" Check your API key
:lua print(vim.env.OPENROUTER_API_KEY)

" Test with curl
" See test_api.sh for example
```

### System Prompt Not Loading

```bash
# Check file exists
ls -l ~/autocomplete-plugin/SYSTEM_PROMPT.md

# Check content
cat ~/autocomplete-plugin/SYSTEM_PROMPT.md

# Make sure prompt is in code block with triple backticks
```

## Advanced Usage

### Query Database Directly

```bash
# Total completions
sqlite3 ~/.local/share/nvim/autocomplete.db \
  "SELECT COUNT(*) FROM completions;"

# Average cost by model
sqlite3 ~/.local/share/nvim/autocomplete.db \
  "SELECT model, AVG(cost) FROM completions GROUP BY model;"

# Acceptance rate
sqlite3 ~/.local/share/nvim/autocomplete.db \
  "SELECT model,
   CAST(SUM(accepted) AS FLOAT) / COUNT(*) AS acceptance_rate
   FROM completions
   GROUP BY model;"

# Recent liked completions
sqlite3 ~/.local/share/nvim/autocomplete.db \
  "SELECT model, completion, timestamp
   FROM completions
   WHERE liked = 1
   ORDER BY timestamp DESC
   LIMIT 10;"
```

### Export Data

```bash
# Export to CSV
sqlite3 -header -csv ~/.local/share/nvim/autocomplete.db \
  "SELECT * FROM completions;" > completions.csv

# Export to JSON
sqlite3 ~/.local/share/nvim/autocomplete.db \
  ".mode json
   SELECT * FROM completions;" > completions.json
```

### Backup Database

```bash
# Create backup
cp ~/.local/share/nvim/autocomplete.db \
   ~/autocomplete-backup-$(date +%Y%m%d).db

# Restore from backup
cp ~/autocomplete-backup-20260105.db \
   ~/.local/share/nvim/autocomplete.db
```

## Performance Tips

1. **Use faster models** for simple completions (DeepSeek, Gemini)
2. **Use premium models** for complex logic (Claude with thinking)
3. **Adjust max_tokens** - Lower = faster, cheaper
4. **Temperature 0.2-0.3** - Good for code (deterministic)
5. **Cache frequently** - Review and accept good completions quickly

## Cost Management

```bash
# Check spending
python3 -c "
import sqlite3
conn = sqlite3.connect('$HOME/.local/share/nvim/autocomplete.db')
total_cost = conn.execute('SELECT SUM(cost) FROM completions').fetchone()[0]
print(f'Total spent: \${total_cost:.2f}')
conn.close()
"

# Set budget alerts (add to shell)
alias autocomplete-cost="sqlite3 ~/.local/share/nvim/autocomplete.db 'SELECT SUM(cost) FROM completions'"
```

---

For more help, see README.md or check the examples in MODEL_COMPARISON.md after running `python3 generate_examples.py`.
