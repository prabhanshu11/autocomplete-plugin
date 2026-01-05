#!/usr/bin/env lua

-- Simple test script to verify OpenRouter API works
local json = require("json") or require("dkjson")

local api_key = "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"
local model = "anthropic/claude-3.5-haiku"

local test_prompt = [[function add(a, b) {
  <CURSOR>
}]]

local body = {
  model = model,
  max_tokens = 100,
  temperature = 0.3,
  messages = {
    {
      role = "system",
      content = "Act like an intelligent autocomplete. Output ONLY the completion text, no explanations."
    },
    {
      role = "user",
      content = test_prompt
    }
  }
}

local body_json = json.encode(body)

-- Using curl for the test
local cmd = string.format(
  [[curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer %s" \
  -H "HTTP-Referer: https://github.com/autocomplete-plugin" \
  -H "X-Title: Neovim Autocomplete Test" \
  -d '%s']],
  api_key,
  body_json:gsub("'", "'\\''")
)

print("Testing OpenRouter API connection...")
print("Model: " .. model)
print("Test prompt: Complete a simple function\n")

local handle = io.popen(cmd)
local response = handle:read("*a")
handle:close()

print("Response:")
print(response)
print("\n---")

local ok, data = pcall(json.decode, response)
if ok and data.choices and data.choices[1] then
  print("\n✓ API connection successful!")
  print("Completion: " .. (data.choices[1].message.content or ""))
else
  print("\n✗ API test failed")
  if data and data.error then
    print("Error: " .. (data.error.message or json.encode(data.error)))
  end
end
