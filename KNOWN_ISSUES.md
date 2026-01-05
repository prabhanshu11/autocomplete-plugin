# Known Issues

## OpenRouter API Key Disabled Issue (2026-01-06)

**Symptom:**
- Plugin was showing error: `OpenRouter API Error: {"error":{"message":"User not found."}}`
- The error appeared as garbled text in the UI
- API requests were returning 401 Unauthorized

**Root Cause:**
- The API key in the OpenRouter dashboard was somehow "disabled"
- Found an option in the UI to re-enable it
- Unclear why it became disabled automatically

**Temporary Fix:**
- Re-enabled the key in OpenRouter dashboard
- Plugin now works correctly

**TODO:**
- [ ] Investigate why OpenRouter API keys get disabled
- [ ] Add better error handling for 401 errors (show clear message about checking API key status)
- [ ] Consider adding API key validation on plugin startup
- [ ] Add documentation about checking API key status in OpenRouter dashboard

---

## Tab Key Behavior Issue (2026-01-06)

**Symptom:**
- When completion suggestion is shown, Tab is bound to accept completion (correct)
- After dismissing completion (Escape), Tab key doesn't return to normal behavior
- Expected: Tab should insert spaces/tabs when no completion is active
- Actual: Tab key seems to remain bound or doesn't work as expected

**Investigation Needed:**
- Keymap cleanup in `clear_preview()` function (line 158-180)
- Buffer-local keymaps may not be properly deleted
- `pcall(vim.keymap.del, 'i', '<Tab>')` might need buffer parameter

**Status:** Under investigation

---

## Completion Persists While Typing (2026-01-06)

**Symptom:**
- When a completion suggestion is shown and user continues typing, the suggestion doesn't clear
- The old suggestion stays visible even though the context has changed
- This blocks new predictions from appearing at the new cursor position
- User must manually dismiss (Escape) or wait for auto-trigger to replace it

**Example Scenario:**
1. Stop typing → completion appears after 2 seconds (e.g., "deleteRM~")
2. Continue typing before accepting → completion should disappear
3. **Expected:** Completion clears, new completion can appear at new position
4. **Actual:** Old completion persists, blocks new predictions

**Root Cause (Suspected):**
- Auto-trigger callback at line 680: `if M.current_completion then return end`
- This prevents new triggers when completion is active
- But typing should clear the active completion first
- Need to clear completion on `TextChangedI` when context changes significantly

**Fix Needed:**
- Clear current completion when user types and context has changed
- Allow new auto-trigger after clearing stale completion
- Possibly check if cursor position has moved significantly from completion position

**Status:** Documented, awaiting fix
