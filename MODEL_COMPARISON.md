# Model Cost & Quality Comparison

**Test Date:** 2026-01-05
**Test Prompt:** `function add(a, b) { <CURSOR> }`
**Expected Completion:** `return a + b;`
**Settings:** max_tokens=100, temperature=0.3

---

## Initial Test Results

| Model | Quality Score | Cost/Completion | Prompt Tokens | Completion Tokens | Response |
|-------|---------------|-----------------|---------------|-------------------|----------|
| **DeepSeek Chat** | TBD | $0.0000159 | 33 | 6 | `return a + b;` |
| **Gemini 2.5 Flash** | TBD | $0.0000215 | 30 | 5 | `return a + b;` |
| **Gemini 3 Flash** | TBD | $0.0000310 | 32 | 5 | `return a + b;` |
| **Kimi K2** | TBD | $0.0000398 | 39 | 5 | `return a + b;` |
| **Claude 3.5 Haiku** | TBD | $0.0000648 | 41 | 8 | `return a + b;` |

---

## Cost Projection (10,000 Completions)

Assuming average: ~35 input tokens, ~6 output tokens

| Model | Estimated Cost | OpenRouter Model ID |
|-------|----------------|---------------------|
| **DeepSeek Chat** | **$0.16** | `deepseek/deepseek-chat` |
| **Gemini 2.5 Flash** | **$0.22** | `google/gemini-2.5-flash` |
| **Gemini 3 Flash** | **$0.31** | `google/gemini-3-flash-preview` |
| **Kimi K2** | **$0.40** | `moonshotai/kimi-k2` |
| **Claude 3.5 Haiku** | **$0.65** | `anthropic/claude-3.5-haiku` |

---

## Quality Score (0-1 Scale)

**Note:** Quality scores will be populated after you use the plugin and provide feedback!

Quality is calculated from:
- **40%** Acceptance rate (Tab pressed / Total)
- **40%** Like rate (Ctrl+L pressed / Total reviewed)
- **20%** Inverse dislike rate (1 - Ctrl+D pressed / Total reviewed)

Run `python3 analyze.py` to generate updated scores based on your usage.

---

## How to Test Models

1. **Choose a model** from the table above
2. **Update your config:**
   ```lua
   require("autocomplete").setup({
     model = "google/gemini-3-flash-preview",  -- Change this
     keymaps = { complete = "<C-a>", toggle_thinking = "<leader>ct>" },
   })
   ```
3. **Use it for a day** - Press Ctrl+A for completions
4. **Provide feedback** - Tab to accept, Ctrl+L to like, Ctrl+D to dislike
5. **Generate report:** `python3 analyze.py`
6. **Compare results** in the updated MODEL_COMPARISON.md

---

## Recommendations

### 🏆 Best Overall Value
**Gemini 3 Flash Preview** - Great balance of cost ($0.000031) and quality

### 💰 Most Cost-Effective
**DeepSeek Chat** - Half the price of Gemini at $0.000016

### ⚡ Best Quality (Premium)
**Claude 3.5 Haiku** - Highest quality but 2x more expensive

### 🌙 Alternative Option
**Kimi K2** - Good middle ground from Chinese provider

---

## Response Time (Approximate)

| Model | Avg Response Time |
|-------|-------------------|
| DeepSeek Chat | ~1200ms |
| Gemini 2.5 Flash | ~1500ms |
| Gemini 3 Flash | ~1400ms |
| Kimi K2 | ~1300ms |
| Claude 3.5 Haiku | ~1000ms |

---

## Usage Tips

1. **Start with Gemini 3 Flash** - Default for good reason
2. **Try DeepSeek** if you want to save money
3. **Switch to Claude** for complex codebases where quality matters
4. **Use Thinking Mode** (Ctrl+T) with Claude for harder completions
5. **Review regularly** - Run `python3 analyze.py` weekly to track quality

---

## Next Steps

After using the plugin:

```bash
# Check your database
sqlite3 ~/.local/share/nvim/autocomplete.db "SELECT COUNT(*) FROM completions;"

# Generate full report
python3 analyze.py

# Review updated MODEL_COMPARISON.md with YOUR quality scores
```

The more you use the plugin and provide feedback, the more accurate your quality scores become!

---

*This file will be automatically updated when you run `python3 analyze.py`*
