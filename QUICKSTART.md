# Quick Start Guide

## Test Results ✓

API connection verified! Test completion:
- **Prompt:** `function add(a, b) { <CURSOR> }`
- **Response:** `return a + b;`
- **Cost:** $0.000065 per completion
- **Model:** Claude 3.5 Haiku

## Installation (3 minutes)

### Step 1: Install plenary.nvim

If you don't have it already:

```lua
-- In your lazy.nvim plugins:
{ "nvim-lua/plenary.nvim" }

-- Or with packer:
use "nvim-lua/plenary.nvim"
```

### Step 2: Add the plugin

**Option A: lazy.nvim (recommended)**

Add to `~/.config/nvim/lua/plugins/autocomplete.lua`:

```lua
return {
  {
    dir = vim.fn.expand("~/autocomplete-plugin"),
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("autocomplete").setup({
        keymaps = {
          complete = "<C-a>",           -- Ctrl+A to autocomplete
          toggle_thinking = "<leader>ct", -- Toggle thinking mode
        },
      })
    end,
  }
}
```

**Option B: Manual (no plugin manager)**

```bash
# Copy to Neovim runtime
mkdir -p ~/.config/nvim/pack/autocomplete/start/
cp -r ~/autocomplete-plugin ~/.config/nvim/pack/autocomplete/start/
```

Add to `~/.config/nvim/init.lua`:

```lua
require("autocomplete").setup({
  keymaps = {
    complete = "<C-a>",
    toggle_thinking = "<leader>ct",
  },
})
```

### Step 3: Restart Neovim

```bash
nvim
```

## Usage

### Trigger Autocomplete

1. Open any code file
2. Start typing (e.g., `function multiply(x, y) {`)
3. Press `Ctrl+A` in insert mode
4. Wait ~1 second for completion
5. The completion appears at your cursor

### Toggle Extended Thinking

In normal mode, press `<leader>ct` to toggle thinking mode:
- **OFF** (default): Fast completions
- **ON**: More thorough reasoning (uses more tokens, slower)

### Commands

- `:ClaudeComplete` - Trigger completion (same as Ctrl+A)
- `:ClaudeToggleThinking` - Toggle thinking mode (same as leader+ct)

## Try Different Models

Edit your config:

```lua
require("autocomplete").setup({
  model = "google/gemini-flash-1.5",  -- Google's model
  -- model = "meta-llama/llama-3.1-8b-instruct",  -- Open source
  -- model = "anthropic/claude-3.5-sonnet",  -- More powerful
  keymaps = { complete = "<C-a>", toggle_thinking = "<leader>ct>" },
})
```

See all models at [openrouter.ai/models](https://openrouter.ai/models)

## Troubleshooting

**Nothing happens when I press Ctrl+A**
- Check `:messages` for errors
- Ensure plenary.nvim is installed
- Try `:ClaudeComplete` command instead

**API Error**
- The embedded key should work for testing
- Check internet connection
- Try a different model

**Completion is too long/short**
- Adjust `max_tokens` in setup (default: 200)

**Want different keybinding**
- Change `complete = "<C-a>"` to any key combo

## Example Session

```javascript
// Type this:
function calculateTotal(items) {
  // [Press Ctrl+A here]

// Claude might complete with:
  return items.reduce((sum, item) => sum + item.price, 0);
}
```

## Cost Tracking

Check your usage at [openrouter.ai](https://openrouter.ai/activity) - with Haiku, typical usage costs pennies per day.

## Next Steps

- Customize the system prompt in `lua/autocomplete.lua:50` for different behavior
- Adjust `temperature` (0-1) for more/less creative completions
- Try different models for different use cases
- **Don't forget to change the API key when done testing!**
