" Prevent loading twice
if exists('g:loaded_claude_autocomplete')
  finish
endif
let g:loaded_claude_autocomplete = 1

" Default configuration will be handled in Lua setup()
