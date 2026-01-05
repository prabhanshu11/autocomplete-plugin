#!/bin/bash

API_KEY="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"
MODEL="anthropic/claude-3.5-haiku"

echo "Testing OpenRouter API connection..."
echo "Model: $MODEL"
echo ""

response=$(curl -s -X POST "https://openrouter.ai/api/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -H "HTTP-Referer: https://github.com/autocomplete-plugin" \
  -H "X-Title: Neovim Autocomplete Test" \
  -d '{
    "model": "'"$MODEL"'",
    "max_tokens": 100,
    "temperature": 0.3,
    "messages": [
      {
        "role": "system",
        "content": "Act like an intelligent autocomplete. Output ONLY the completion text, no explanations."
      },
      {
        "role": "user",
        "content": "function add(a, b) {\n  <CURSOR>\n}"
      }
    ]
  }')

echo "Full Response:"
echo "$response" | jq '.' 2>/dev/null || echo "$response"
echo ""

# Check if successful
if echo "$response" | grep -q '"choices"'; then
  echo "✓ API connection successful!"
  completion=$(echo "$response" | jq -r '.choices[0].message.content' 2>/dev/null)
  if [ ! -z "$completion" ] && [ "$completion" != "null" ]; then
    echo ""
    echo "Completion received:"
    echo "$completion"
  fi
else
  echo "✗ API test failed"
  error=$(echo "$response" | jq -r '.error.message' 2>/dev/null)
  if [ ! -z "$error" ] && [ "$error" != "null" ]; then
    echo "Error: $error"
  fi
fi
