vim.opt.rtp:prepend(vim.fn.fnamemodify(os.getenv("PLUGIN_DIR") or ".", ":p"))
local t = require("autocomplete")._tidy
local cases = {
  { "rotate the key", "key and", " rotate the key" },
  { "and rotate the key", "key and", " rotate the key" },           -- echo of 'and' stripped, then space
  { "complete", "auto", " complete" },                               -- mid-word: known limitation, space added
  { "bar()", "foo.", "bar()" },                                      -- after '.' no space
  { "```lua\nprint(1)\n```", "x = 1\n", "print(1)" },                -- fences stripped
  { "   ", "abc", nil },
  { "- Wednesday: tests", "and\n", "- Wednesday: tests" },           -- after newline no space
}
local fail = 0
for _, c in ipairs(cases) do
  local got = t(c[1], c[2])
  if got ~= c[3] then fail = fail + 1; print(string.format("FAIL before=%q text=%q got=%q want=%q", c[2], c[1], tostring(got), tostring(c[3]))) end
end
print("tidy cases failed:", fail)
vim.cmd("qa!")
