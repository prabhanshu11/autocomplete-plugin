return {
  {
    "autocomplete-plugin",
    dir = "/home/prabhanshu/autocomplete-plugin",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("autocomplete").setup({
        api_key = "YOUR_OPENROUTER_API_KEY_HERE",  -- Get from https://openrouter.ai/keys
        model = "google/gemini-3-flash-preview",
        auto_trigger = true,
        auto_trigger_delay = 2000,
      })
    end,
  },
}
