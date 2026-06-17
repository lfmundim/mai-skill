# Good Prompts — MAI Skill

Patterns that reliably produce clean, complete results from the executor model.

---

## 1. Self-contained with exact file and stack

```
Stack: Python/Flask, SQLAlchemy, SQLite
Key files: app.py (routes), models.py (ORM models)

TASK: Add a POST /api/rate-limit-test route that returns 429 if the same IP
has made more than 10 requests in the last 60 seconds. Use an in-memory dict keyed
by IP address.

CONSTRAINTS:
- Do not modify any existing route
- The counter dict must be module-level (not per-request)
- Return JSON: {"error": "rate limit exceeded", "retry_after": <seconds>}

VERIFY: grep for "rate_limit" in app.py and confirm the function exists.

OUTPUT FORMAT:
Modified: app.py
Does: adds POST /api/rate-limit-test with in-memory per-IP rate limiting
No other prose.
```

**Why it works:** exact file, exact signature constraints, grep-based verify, one task.

---

## 2. Fix a specific bug with context

```
Stack: TypeScript/Express
Key files: src/auth/middleware.ts (JWT verification)

TASK: Fix the JWT verification in validateToken() — it currently calls
jwt.verify(token, secret) but never handles the TokenExpiredError exception,
causing the server to return 500 instead of 401 on expired tokens.

CONSTRAINTS:
- Catch TokenExpiredError specifically (not a blanket catch)
- Return: res.status(401).json({ error: "token expired" })
- Do not change the signature of validateToken

VERIFY: grep for "TokenExpiredError" in src/auth/middleware.ts.

OUTPUT FORMAT:
Modified: src/auth/middleware.ts
Does: catches TokenExpiredError and returns 401
No other prose.
```

---

## 3. Add a field to an existing data model

```
Stack: Python/Django, PostgreSQL
Key files: users/models.py (User model), users/serializers.py (UserSerializer)

TASK: Add an optional "display_name" CharField (max_length=100, blank=True) to the
User model in users/models.py, and expose it in UserSerializer.

CONSTRAINTS:
- Field must be nullable=False, blank=True, default=""
- Add it after the "email" field in the model definition
- Add "display_name" to UserSerializer.Meta.fields list

VERIFY: grep for "display_name" in users/models.py and users/serializers.py.
```

---

## 4. Read-first exploration (sub-task 1 of a complex task)

```
Stack: Go/Gin
Key files: internal/handlers/ (HTTP handlers), internal/store/ (data layer)

TASK: Read internal/handlers/orders.go and internal/store/order_store.go.
Report: the signature of the CreateOrder handler, the interface method it calls on
the store, and any validation that already exists on the incoming request body.

Do NOT modify any files.

VERIFY: Report the exact function signatures you found.
```

---

## 5. Refactoring with an anchor constraint

```
Stack: Node.js/Express
Key files: src/routes/users.js (user CRUD routes)

TASK: Extract the inline validation logic in the POST /users handler into a separate
function called validateUserInput(body). The function should return { valid: boolean,
errors: string[] }.

The existing inline validation starts at the comment "// validate input fields".
Move it to a standalone function above the route definitions.

CONSTRAINTS:
- validateUserInput must be defined before it is called
- The route handler must call validateUserInput and check valid === true
- Do not change any other route

VERIFY: grep for "function validateUserInput" in src/routes/users.js.
```

---

## Patterns that always improve results

| Pattern | Example |
|---|---|
| Name the exact file | `Key files: src/auth.py` |
| State the exact line/anchor | `The function starts at "async def login("` |
| Give the full target signature | `def validate(data: dict) -> tuple[bool, list[str]]:` |
| One task per prompt | Never "also add tests" or "also update the docs" |
| Grep-based VERIFY | `grep for "def validate" in auth.py` |
| Explicit OUTPUT FORMAT | Reduces prose, makes diff easier to review |
