# Architecture Documentation

## Overview

This plugin follows a three-layer architecture:

```
┌─────────────────────────────────────────┐
│         User Interface Layer            │
│  (Neovim keybindings, virtual text)     │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│         Business Logic Layer            │
│  (Completion management, state)         │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│         Data Layer                      │
│  (SQLite, OpenRouter API, file I/O)     │
└─────────────────────────────────────────┘
```

## Directory Structure

```
autocomplete-plugin/
│
├── lua/
│   └── autocomplete.lua          # Main plugin code (single file)
│
├── plugin/
│   └── autocomplete.vim          # Vim initialization (loads Lua)
│
├── docs/
│   ├── ARCHITECTURE.md           # This file
│   ├── CONTRIBUTING.md           # How to contribute
│   ├── DEVELOPMENT.md            # Dev setup and workflow
│   └── API.md                    # Internal API reference
│
├── scripts/
│   ├── analyze.py                # Analytics generator
│   └── generate_examples.py      # Examples appender
│
├── config/
│   └── SYSTEM_PROMPT.md          # User-editable prompt
│
├── docs/user/
│   ├── README.md                 # Main user documentation
│   ├── QUICKSTART.md             # Fast setup guide
│   ├── USAGE_GUIDE.md            # Detailed usage
│   └── TROUBLESHOOTING.md        # Common issues
│
└── tests/
    └── test_api.sh               # Manual API testing
```

## Component Breakdown

### 1. Core Plugin (`lua/autocomplete.lua`)

**Responsibilities:**
- Manage completion state
- Handle user interactions
- Communicate with OpenRouter API
- Log data to SQLite
- Render virtual text previews

**Key Functions:**

```lua
-- Configuration and state
M.config = {}                    -- Plugin configuration
M.current_completion = {}        -- Active completion state

-- Database operations
init_db()                        -- Create tables and indexes
log_completion(data)             -- Insert completion record
update_review(id, accepted, liked) -- Update user feedback

-- User interactions
M.autocomplete()                 -- Trigger new completion
M.accept_completion()            -- Insert completion
M.reject_completion()            -- Get new completion
M.like_completion()              -- Mark as liked
M.dislike_completion()           -- Mark as disliked
M.dismiss_completion()           -- Cancel

-- Internal helpers
get_context()                    -- Extract code around cursor
load_system_prompt()             -- Read from SYSTEM_PROMPT.md
call_api()                       -- Async OpenRouter call
show_preview()                   -- Display virtual text
clear_preview()                  -- Remove virtual text
```

### 2. Analytics Layer (`analyze.py`)

**Responsibilities:**
- Query SQLite database
- Calculate quality scores
- Generate markdown reports
- Provide recommendations

**Key Functions:**

```python
get_db_path()                    # Find database location
calculate_quality_score()        # Compute 0-1 score
analyze_database()               # Aggregate statistics
generate_markdown_report()       # Create MODEL_COMPARISON.md
```

**Quality Score Formula:**
```python
quality = (
    0.4 * (accepted / total) +           # Acceptance rate
    0.4 * (liked / reviewed) +           # Like rate
    0.2 * (1 - disliked / reviewed)      # Inverse dislike
)
```

### 3. Examples Layer (`generate_examples.py`)

**Responsibilities:**
- Query completions with feedback
- Format as markdown examples
- Append to report file
- Create notice file

**Key Functions:**

```python
get_examples()                   # Query recent reviewed completions
generate_examples_markdown()     # Format as markdown
append_examples_to_report()      # Append to file
create_generated_notice()        # Create notice file
```

## Data Flow

### Completion Request Flow

```
1. User presses Ctrl+A
   └─> M.autocomplete()

2. Get code context
   └─> get_context()
       ├─> Extract code before cursor
       └─> Extract code after cursor

3. Load system prompt
   └─> load_system_prompt()
       ├─> Read SYSTEM_PROMPT.md
       └─> Extract from code block

4. Call API (async)
   └─> call_api()
       ├─> Build request body
       ├─> Add thinking if Claude model
       └─> POST to OpenRouter

5. Receive response
   └─> callback()
       ├─> Extract completion text
       ├─> Log to database
       ├─> Show virtual text preview
       └─> Set up temporary keymaps

6. User reviews
   └─> Tab/Ctrl+R/Ctrl+L/Ctrl+D/Esc
       └─> Update database with feedback
```

### Analytics Generation Flow

```
1. Run analyze.py
   └─> analyze_database()

2. Query per-model statistics
   ├─> Total completions
   ├─> Acceptance rate
   ├─> Like/dislike counts
   ├─> Cost and timing
   └─> Calculate quality scores

3. Generate markdown report
   └─> MODEL_COMPARISON.md
       ├─> Overall statistics
       ├─> Model comparison table
       ├─> Cost projections
       └─> Recommendations

4. Run generate_examples.py
   └─> get_examples()

5. Query reviewed completions
   ├─> Filter for liked/disliked
   └─> Order by timestamp DESC

6. Append to report
   └─> MODEL_COMPARISON.md
       └─> ## Real Completion Examples
           ├─> 👍 Liked examples
           └─> 👎 Disliked examples
```

## State Management

### Plugin State

```lua
M.current_completion = {
  text = "...",              -- Completion text
  request_id = "...",        -- Unique ID for database
  ns_id = 123,               -- Namespace for virtual text
  accepted = false,          -- Has user accepted?
  keymaps_set = true         -- Are temp keymaps active?
}
```

**State Transitions:**

```
[No completion]
    │
    ├─ Ctrl+A ──> [Preview shown]
    │                 │
    │                 ├─ Tab ──> [Accepted] ──> [No completion]
    │                 ├─ Ctrl+R ──> [Rejected] ──> [Preview shown] (new)
    │                 ├─ Ctrl+L ──> [Liked] (preview remains)
    │                 ├─ Ctrl+D ──> [Disliked] (preview remains)
    │                 └─ Esc ──> [Dismissed] ──> [No completion]
    │
    └─ (any other key) ──> [No completion]
```

### Database State

```sql
-- Completion lifecycle in database:

1. Created: INSERT with default values
   accepted = 0
   liked = NULL
   reviewed_at = NULL

2. Reviewed: UPDATE on user action
   accepted = 1 (if Tab pressed)
   liked = 1 or 0 (if Ctrl+L or Ctrl+D)
   reviewed_at = timestamp

3. Analyzed: SELECT for statistics
   Used in quality score calculation
```

## API Communication

### OpenRouter Request Format

```json
POST https://openrouter.ai/api/v1/chat/completions
Headers:
  Content-Type: application/json
  Authorization: Bearer <api_key>
  HTTP-Referer: https://github.com/autocomplete-plugin
  X-Title: Neovim Autocomplete

Body:
{
  "model": "google/gemini-3-flash-preview",
  "max_tokens": 200,
  "temperature": 0.3,
  "messages": [
    {
      "role": "system",
      "content": "<system_prompt>"
    },
    {
      "role": "user",
      "content": "<code_before><CURSOR><code_after>"
    }
  ],
  "thinking": {  // Optional: Claude models only
    "type": "enabled",
    "budget_tokens": 1000
  }
}
```

### OpenRouter Response Format

```json
{
  "id": "gen-...",
  "choices": [
    {
      "message": {
        "content": "return a + b;"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 32,
    "completion_tokens": 5,
    "total_tokens": 37,
    "cost": 0.000031
  }
}
```

## Database Schema

### completions Table

```sql
CREATE TABLE completions (
  -- Identity
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  request_id TEXT NOT NULL,           -- Unique per request
  timestamp TEXT NOT NULL,            -- ISO format

  -- Model info
  model TEXT NOT NULL,                -- e.g., "google/gemini-3-flash-preview"

  -- Context
  prompt_before TEXT NOT NULL,        -- Code before cursor
  prompt_after TEXT NOT NULL,         -- Code after cursor
  filetype TEXT,                      -- e.g., "python", "javascript"

  -- Completion
  completion TEXT NOT NULL,           -- Generated text

  -- Metrics
  prompt_tokens INTEGER,              -- Input tokens used
  completion_tokens INTEGER,          -- Output tokens used
  total_tokens INTEGER,               -- Sum
  cost REAL,                          -- USD cost
  response_time_ms INTEGER,           -- Latency

  -- Feedback
  accepted INTEGER DEFAULT 0,         -- 1 if Tab pressed
  liked INTEGER DEFAULT NULL,         -- 1=liked, 0=disliked, NULL=not reviewed
  reviewed_at TEXT                    -- When feedback given
);

-- Indexes for fast queries
CREATE INDEX idx_model ON completions(model);
CREATE INDEX idx_timestamp ON completions(timestamp);
CREATE INDEX idx_accepted ON completions(accepted);
CREATE INDEX idx_liked ON completions(liked);
```

## Virtual Text Rendering

### How Preview Works

```lua
-- 1. Create namespace
local ns_id = vim.api.nvim_create_namespace('autocomplete_preview')

-- 2. Show first line as overlay
vim.api.nvim_buf_set_extmark(0, ns_id, row, col, {
  virt_text = {{"completion_text", "Comment"}},
  virt_text_pos = "overlay",  -- Overlays at cursor
})

-- 3. Show remaining lines as virtual lines
vim.api.nvim_buf_set_extmark(0, ns_id, row, 0, {
  virt_lines = {{{"  more_text", "Comment"}}},
  virt_lines_above = false,  -- Below current line
})

-- 4. Clear on action
vim.api.nvim_buf_clear_namespace(0, ns_id, 0, -1)
```

### Highlight Groups Used

- `Comment` - For virtual text (grayed out)
  - Customize: `:highlight Comment guifg=#606060`

## Configuration System

### Config Loading Order

```
1. Plugin defaults (lua/autocomplete.lua:4-12)
   ↓
2. Environment variables
   ↓ (OPENROUTER_API_KEY overrides default)
3. User setup() call
   ↓ (All options can be overridden)
4. Runtime (user can change model, etc.)
```

### Config Options

```lua
{
  api_key = string,              -- OpenRouter API key
  model = string,                -- Model ID
  thinking_enabled = boolean,    -- Extended thinking (Claude)
  max_tokens = number,           -- Max completion length
  temperature = number,          -- Randomness (0-1)
  db_path = string,              -- SQLite database path
  system_prompt_file = string,   -- Path to SYSTEM_PROMPT.md
  keymaps = {
    complete = string,           -- Trigger key
    toggle_thinking = string     -- Thinking toggle key
  }
}
```

## Error Handling

### API Errors

```lua
-- Non-200 response
if response.status ~= 200 then
  vim.notify("OpenRouter API Error: " .. response.body, vim.log.levels.ERROR)
  return
end

-- Invalid JSON
local ok, data = pcall(vim.json.decode, response.body)
if not ok then
  vim.notify("Failed to parse API response", vim.log.levels.ERROR)
  return
end
```

### Database Errors

```lua
-- Database operations use detached jobs
vim.fn.jobstart({"bash", "-c", sql}, {detach = true})

-- Errors are silent (logged to Neovim messages)
-- Database will be created if missing
-- Failed inserts don't block the plugin
```

### File I/O Errors

```lua
-- System prompt loading is safe
local file = io.open(prompt_file, "r")
if not file then
  return default_prompt  -- Fallback to default
end
```

## Security Considerations

### ⚠️ SQL Injection Protection

```lua
-- CURRENT: String concatenation (VULNERABLE!)
local sql = string.format([[
  INSERT INTO completions VALUES ('%s', '%s', ...)
]], data.completion, data.model)

-- TODO: Use parameterized queries
-- Consider using lua-sqlite3 library for proper parameter binding
```

### ⚠️ API Key Exposure

```lua
-- CURRENT: Hardcoded in source (DEVELOPMENT ONLY!)
api_key = "sk-or-v1-..."

-- PRODUCTION: Must use environment variable
api_key = os.getenv("OPENROUTER_API_KEY")
```

### Prompt Injection

- System prompt is read from file, user-controlled
- Could affect completion quality but not security
- API is read-only (no dangerous operations)

## Performance Characteristics

### Time Complexity

- `get_context()`: O(n) where n = buffer lines
- `show_preview()`: O(1) for extmark creation
- `log_completion()`: O(1) async job spawn
- `call_api()`: O(network latency) async

### Space Complexity

- Database grows O(completions)
- In-memory state: O(1) per completion
- Virtual text: O(completion length)

### Bottlenecks

1. **API latency** (1-2 seconds)
   - Mitigated by async calls
   - User can continue typing

2. **Database writes** (negligible)
   - Async detached jobs
   - No blocking

3. **Virtual text rendering** (negligible)
   - Neovim handles efficiently
   - Cleared immediately on action

## Extension Points

### Adding New Models

1. Add model to config
2. Test with `test_api.sh`
3. Update documentation
4. Run analytics after testing

### Custom Quality Metrics

Edit `analyze.py`:
```python
def calculate_quality_score(accepted, liked, disliked, total):
    # Modify weights here
    return custom_formula()
```

### Additional Feedback Options

1. Add new keymap in `M.autocomplete()`
2. Create handler function
3. Update database schema if needed
4. Update `update_review()` function

### New Analytics Reports

1. Create new Python script
2. Query database
3. Generate markdown
4. Update README with instructions

## Testing Strategy

### Manual Testing

```bash
# 1. API connectivity
./test_api.sh

# 2. Database creation
rm ~/.local/share/nvim/autocomplete.db
# Start Neovim, trigger completion
# Check database exists

# 3. All keybindings
# In Neovim, test each: Ctrl+A, Tab, Ctrl+R, Ctrl+L, Ctrl+D, Esc

# 4. Analytics
python3 analyze.py
python3 generate_examples.py
# Check MODEL_COMPARISON.md
```

### Automated Testing (TODO)

```lua
-- Unit tests for core functions
describe("get_context", function()
  it("extracts code before cursor", function()
    -- Test implementation
  end)
end)
```

## Deployment Checklist

Before deploying to production:

- [ ] Remove hardcoded API key
- [ ] Add environment variable check
- [ ] Add SQL injection protection
- [ ] Add comprehensive error messages
- [ ] Test with fresh database
- [ ] Verify all keybindings work
- [ ] Test system prompt loading
- [ ] Run analytics scripts
- [ ] Review documentation completeness

## Future Improvements

### High Priority
- [ ] Parameterized SQL queries
- [ ] Automated tests
- [ ] Better error recovery
- [ ] Rate limiting protection

### Medium Priority
- [ ] Cache frequent completions
- [ ] Multi-cursor support
- [ ] Web dashboard for analytics
- [ ] Model auto-switching

### Low Priority
- [ ] Custom highlight themes
- [ ] Completion history navigation
- [ ] Export to other formats (JSON, CSV)
- [ ] Team analytics aggregation

## Maintenance Notes

### Regular Tasks

**Weekly:**
- Review analytics reports
- Check database size
- Monitor API costs

**Monthly:**
- Clean old completions
- Vacuum database
- Update documentation

**Quarterly:**
- Review security
- Update dependencies
- Test new models

### Breaking Changes to Avoid

- Don't change database schema without migration
- Don't modify config structure without backwards compatibility
- Don't rename core functions without deprecation warnings
- Don't change file locations without symlinks

## Contact & Support

- **Issues:** GitHub issues
- **Discussions:** GitHub discussions
- **Contributions:** See CONTRIBUTING.md
- **Security:** Email (add contact)

---

*Last updated: 2026-01-05*
*Version: 1.0.0*
