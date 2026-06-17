# Anti-Patterns — MAI Skill

What fails, why, and how to fix it.

---

## 1. Multiple tasks in one prompt

**Bad:**
```
TASK: Add rate limiting to the POST /auth route, update the error messages to use
our standard format, and add a test for the new endpoint.
```
**Why it fails:** The executor focuses on whichever task it finds easiest, skips the
rest, or partially implements all three and makes none of them correct.

**Fix:** Three separate delegate calls, each with one task.

---

## 2. No file specified — executor guesses

**Bad:**
```
TASK: Add input validation to the user creation endpoint.
```
**Why it fails:** The executor searches, finds several candidate files, picks the wrong
one, or writes validation in a helper file nobody imports.

**Fix:**
```
Key files: src/routes/users.py (POST /users handler)
TASK: Add input validation to the POST /users handler in src/routes/users.py.
```

---

## 3. Vague imperative — "improve" / "fix" / "clean up"

**Bad:**
```
TASK: Improve the error handling in the auth module.
```
**Why it fails:** "Improve" has no defined end state. The executor rewrites things
it shouldn't, or makes no change and exits 0.

**Fix:** Describe the exact before/after state:
```
TASK: Add a try/except around the jwt.decode() call in auth.py that catches
jwt.DecodeError and returns HTTP 401 instead of propagating the exception.
```

---

## 4. VERIFY with file re-read instead of grep

**Bad:**
```
VERIFY: Read auth.py and confirm the change is there.
```
**Why it fails:** "Read and confirm" is vague — the executor may read the file,
decide everything looks fine, and return success without actually making the change.

**Fix:**
```
VERIFY: grep for "jwt.DecodeError" in auth.py and confirm it exists.
```

---

## 5. Prompt contains shell-unsafe characters inline

**Bad (passed inline to a bash variable):**
```bash
PROMPT="TASK: Add `config['rate_limit']['max_requests']` to the settings dict."
```
**Why it fails:** Backticks, `{`, `}`, `$`, `'` in a bash variable cause shell
expansion, truncation, or injection.

**Fix:** The `copilot-delegate` script writes the prompt to a temp file automatically
when called through the SKILL.md orchestration. This is why you should **always call
the delegate through the skill**, never construct and pass the prompt manually in bash.

---

## 6. Re-delegating without reading the diff first

**Bad:**
```
# First run exited non-zero — immediately re-delegate the same prompt
~/tools/copilot-delegate "$WORKDIR" "$SAME_PROMPT" "$MODEL"
```
**Why it fails:** If the first run partially succeeded (e.g. wrote 60% of the change),
the second run will see different file state and may duplicate or conflict with what's
already there.

**Fix:** Always run `git diff` after a failed run. Understand what was done before
deciding whether to re-delegate, fix manually, or revert.

---

## 7. Bundling a review fix with other instructions

**Bad (review fix prompt):**
```
TASK: Fix the missing nil check in getUserById(), and also update the related
unit tests to cover the nil case, and rename the function to findUserById.
```
**Why it fails:** The review loop re-delegates one issue at a time. Bundling multiple
changes makes the review harder to validate and increases the chance of new issues.

**Fix:** One fix per re-delegation prompt in the `--with-review N` loop.

---

## 8. Delegating a trivial change

**Bad:**
```
/mai change the error message on line 42 of app.py from "not found" to "resource not found"
```
**Why it fails:** The overhead of model selection, delegate launch, and diff review
exceeds the cost of just editing the file directly.

**Fix:** Edit the file directly. The SKILL.md Step 4 table marks this as "Trivial —
skip delegation."

---

## 9. Not specifying the language/framework stack

**Bad:**
```
Key files: handler.py

TASK: Add caching to the fetch_user function.
```
**Why it fails:** "Caching" in Flask means something different than in Django, FastAPI,
or a raw asyncio app. The executor guesses and may import the wrong caching library.

**Fix:**
```
Stack: Python/FastAPI, Redis (via aioredis)
Key files: handlers/user.py (async fetch_user function)
```

---

## 10. Asking the executor to "check" or "verify" — those are review tasks

**Bad:**
```
TASK: Check that the migration is correct and fix any issues you find.
```
**Why it fails:** "Check and fix" is an open-ended exploration that produces
inconsistent results. The executor either does nothing (checks, finds no obvious issue)
or rewrites the whole migration.

**Fix:** Use `--with-review N` to have the **orchestrator** (Copilot) review the diff
after a focused implementation task. Keep executor prompts imperative and specific.
