-- Example Neovim configuration for testing the autocomplete plugin
-- Add this to your init.lua or test it in a minimal config

-- 1. Using lazy.nvim (recommended)
return {
  {
    dir = vim.fn.expand("~/autocomplete-plugin"),
    dependencies = {
      "nvim-lua/plenary.nvim"
    },
    config = function()
      require("autocomplete").setup({
        -- API key is already embedded for testing
        -- model = "anthropic/claude-3.5-haiku",  -- Default, already set

        -- Try other models:
        -- model = "google/gemini-flash-1.5",
        -- model = "meta-llama/llama-3.1-8b-instruct",
        -- model = "anthropic/claude-3.5-sonnet",  -- More powerful, more expensive

        thinking_enabled = false,  -- Toggle with <leader>ct
        max_tokens = 200,
        temperature = 0.3,

        keymaps = {
          complete = "<C-a>",           -- Ctrl+A in insert mode
          toggle_thinking = "<leader>ct", -- Leader+c+t in normal mode
        },
      })

      -- Optional: Show a message when plugin loads
      vim.notify("Claude Autocomplete loaded! Press <C-a> in insert mode", vim.log.levels.INFO)
    end,
  }
}

-- 2. Or for packer.nvim:
--[[
use {
  "~/autocomplete-plugin",
  requires = { "nvim-lua/plenary.nvim" },
  config = function()
    require("autocomplete").setup({
      keymaps = {
        complete = "<C-a>",
        toggle_thinking = "<leader>ct",
      },
    })
  end,
}
]]

-- 3. Or manual setup (add to init.lua after adding plugin to runtimepath):
--[[
require("autocomplete").setup({
  keymaps = {
    complete = "<C-a>",
    toggle_thinking = "<leader>ct",
  },
})
]]
