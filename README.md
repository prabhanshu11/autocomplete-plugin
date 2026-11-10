# autocomplete-plugin

AI autocomplete for Neovim, backed by OpenRouter. Rewritten 2026-11-10 (v2); the other
`*.md` files in this repo describe the January 2026 v1 (auto-trigger, sqlite log) and are
kept as history.

## What it does

One key in insert mode asks for **three completions of different length for the same
cursor position** (short: a few words · medium: the sentence or line · long: 3 to 8 lines).
The first to arrive shows as ghost text; switch between lengths while it is visible.

| Key | Mode | Action |
|-----|------|--------|
| `Ctrl+Space` | insert | ask for suggestions at the cursor |
| `Tab` | insert, ghost text showing | accept |
| `Space h` / `Space l` | insert, ghost text showing | shorter / longer |
| `Space 1` / `2` / `3` | insert, ghost text showing | short / medium / long |
| `Space m` | insert, ghost text showing | pick the model (picker UI), then re-ask |
| `Ctrl+E` or just typing | insert | dismiss |
| `Space a m` | normal | pick the model |

`Space` is `<leader>`; the leader chords exist **only while ghost text is visible**, so a
plain Space never waits for a chord otherwise. `:AiModel` (curated list with prices),
`:AiModelBrowse` (every OpenRouter model, live prices), `:AiComplete`, `:AiLog`.
The chosen model persists in `stdpath("data")/autocomplete-model`.

## Setup

API key: `$OPENROUTER_API_KEY`, else `pass show api/openrouter/nvim_autocomplete` (first line). The key is
handed to curl through a config on stdin, never on the command line.

lazy.nvim spec (the one used in local-bootstrapping `dotfiles/nvim/lua/plugins/autocomplete-ai.lua`):

```lua
{
  dir = vim.fn.expand("~/Programs/autocomplete-plugin"),
  name = "autocomplete-ai",
  event = "InsertEnter",
  opts = { model = "anthropic/claude-haiku-5.5" },
  config = function(_, opts) require("autocomplete").setup(opts) end,
}
```

Every option and its default is at the top of `lua/autocomplete.lua` (`M.config`): model,
curated model list, context size, the three length instructions, keymaps, highlight.

## Failure behaviour

Offline, bad key, dead model, timeout: **one** `vim.notify` warning per request, nothing
else. No `error()` is ever raised from a callback (v1's stacked "Lua callback" popups came
from exactly that when OpenRouter retired `google/gemini-2.0-flash-001`).

## Tests

```bash
tests/run.sh        # tidy() cases, offline path, and the plugin under your real LazyVim config
tests/run.sh live   # also three real OpenRouter requests (well under 0.01 USD)
```

## Log

`stdpath("data")/autocomplete-log.jsonl`: one line per reply (model, length, ms, ok/err),
accept, and model change. Open it with `:AiLog`.
