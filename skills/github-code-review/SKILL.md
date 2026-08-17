---
name: github-code-review
description: Reviews the current branch as if it were a pull request, comparing it against the base branch, and writes the findings to a CODE_REVIEW.md file at the repo root — explained in plain language for a reader with little context on the codebase, with concrete examples, before/after code, and a step-by-step guide of exactly which lines to comment on and what to write. Use this whenever the user asks to review a branch, review a PR, "check this before I merge", "what's wrong with this branch", "review my changes against main", or wants review findings written to a file rather than delivered as chat commentary. Also use when the user wants a review they can hand to a non-expert or to another coding agent to act on.
---

# PR Review in Plain English

## What this skill is for

Produce a written review of a branch that someone can actually act on **without already knowing
the codebase**. The typical reader is a capable but rusty programmer who now works mostly through
AI coding assistants. They can apply a diff and follow instructions; they cannot decode terse
reviewer shorthand.

That means a finding like "N+1 query in the loop" is a failure of this skill. The same finding
written as "for every order in the list, the code makes a separate trip to the database — 50
orders means 51 queries instead of 1, so the page gets slower the more data a user has" is the
target.

The deliverable is always a file: `CODE_REVIEW.md` at the repository root. This is a review, not
a fix.

## Workflow

### 1. Establish what is under review

```bash
git rev-parse --abbrev-ref HEAD          # the branch acting as the PR
git fetch                                 # make sure the base is current
git log <base>..HEAD --oneline            # commits on this branch
git diff <base>...HEAD                    # three dots: changes since divergence
git diff <base>...HEAD --stat             # size and shape of the change
```

The base branch is `main` unless the user says otherwise (check for `master`, `develop`, or a
release branch if `main` doesn't exist). Three dots matter: `git diff main..HEAD` also shows
changes that landed on main, which pollutes the review with other people's work.

If HEAD is the base branch itself, or the diff is empty, stop and ask the user which branch they
meant instead of reviewing nothing.

### 2. Read beyond the diff

A diff alone hides most real problems. Before judging any change, read:

- the full file around each hunk, not just the changed lines
- the callers of any changed function (`grep`/`rg` for the name) — a signature change breaks them
- existing tests covering the touched area, and whether the PR updated them
- neighbouring code that does something similar, so proposed fixes match house style
- config, migrations, and dependency changes, which carry outsized risk for their line count

If the project has a `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, or lint/style config, read it
and hold the PR to those conventions rather than to generic preferences.

### 3. Analyse

If the `code-review` skill is available in the environment, invoke it and use its analysis as the
backbone of the findings. If it isn't available, work through this checklist directly:

- **Correctness** — does it do what the commits claim? Off-by-one, inverted conditions, wrong
  variable, unhandled `null`/`None`, wrong default.
- **Security** — untrusted input reaching a query, command, path, or template; secrets in code;
  missing authorization check; overly broad permissions; unsafe deserialization.
- **Error handling** — swallowed exceptions, errors logged but execution continuing, failure
  paths that leave data half-written.
- **Edge cases** — empty list, one item, huge list, duplicate submit, concurrent access,
  timezone/locale, unicode, network failure mid-operation.
- **Performance** — queries or network calls inside loops, unbounded memory growth, missing
  index on a new lookup column, repeated work that could be computed once.
- **Tests** — is new behavior covered? Do existing tests still make sense?
- **Fit** — does it match the patterns already in this codebase, or invent a parallel approach?

Report only what is actually there. Two real findings beat eight padded ones — padding makes it
impossible for this reader to tell what matters.

### 4. Write `CODE_REVIEW.md`

Write to the repository root. Use exactly this structure:

```markdown
# Code Review: <branch-name> → <base-branch>

## What this PR does
<3–6 sentences in plain language for someone who has never seen the branch: what problem it
solves, which parts of the system it touches, how big the change is.>

## Verdict
<One short paragraph, stated directly: ready to merge / merge after the fixes below / needs
rework. No hedging.>

## Findings

### Blockers
### Should fix
### Nice to have

## What's good
<Short. Real strengths of the change, so the reader sees it isn't all problems.>

## How to handle this PR — step by step
```

Drop a severity heading entirely if it has no findings.

### Finding format

Every finding, regardless of severity, uses this shape:

```markdown
#### <Short plain-language title>
**Where:** `path/to/file.ext`, lines 42–58
**Severity:** Blocker — <one sentence on why it's in this bucket>

**What's happening:** <the mechanics, in ordinary words. Define jargon on first use.>

**Example:** <a concrete failure with real values and a real sequence of events>

**Why it matters:** <user-visible impact, security exposure, or future maintenance cost. If the
honest answer is "nothing breaks today, but it will bite later", say that.>

**Current code:**
```lang
<minimal snippet — the problem lines plus a little context>
```

**Suggested code:**
```lang
<the replacement, in this codebase's style>
```
```

**Worked example of the tone to aim for:**

> **What's happening:** The code checks whether the user is logged in, but it never checks
> whether *this particular* user owns the invoice they asked for. It only asks "are you
> someone?" and not "is this yours?"
>
> **Example:** User A opens their invoice at `/invoices/1041`. If they change the URL to
> `/invoices/1042`, they get user B's invoice — full name, address, amounts — because the only
> question the code asks is whether *someone* is logged in.
>
> **Why it matters:** Any logged-in customer can read every other customer's billing data by
> editing a number in the address bar. That's a data breach, not a bug.

### The step-by-step section

This is the most important part of the document and it always comes last. It must be executable
top to bottom by someone who follows instructions literally. For every comment the reviewer
should leave, give the file, the exact line numbers, and the **verbatim comment text** — phrased
as a reviewer would say it to the PR author, ready to paste with no editing. For every requested
change, give the replacement code.

Format:

```markdown
## How to handle this PR — step by step

### 1. Comment on `src/api/invoices.py`, line 47
Paste this as a review comment:

> This endpoint checks that the caller is authenticated but never checks that the invoice
> belongs to them — any logged-in user can read any invoice by changing the ID in the URL.
> Could we scope the lookup to the current user?

Suggested change:
```python
- invoice = Invoice.get(invoice_id)
+ invoice = Invoice.get(invoice_id, owner=current_user)
+ if invoice is None:
+     abort(404)
```

### 2. Comment on `src/api/invoices.py`, line 112
...

### 3. Request tests
...

### 4. After the author pushes fixes, verify
- Run `<the project's actual test command>` — all tests pass
- Manually check: log in as one user, request another user's invoice ID, expect 404
- Confirm the changed lines above now read as suggested

### 5. Approve when
- Both blockers are resolved and verified
- The "should fix" items are either fixed or the author has explained why not
```

Use the project's real test/lint/build commands, taken from its `package.json`, `Makefile`,
`pyproject.toml`, CI config, or README — not invented ones.

## Rules that keep this useful

- **Review only.** Do not edit source files, do not commit, do not push, do not post comments to
  GitHub/GitLab. The only file written is `CODE_REVIEW.md`. Verify with `git status` at the end —
  nothing but that file should have changed.
- **Real line numbers.** Every location must come from the actual branch state. Never approximate
  or invent a path or line.
- **Match the codebase.** Every suggested snippet uses the project's existing language version,
  libraries, naming, and error-handling patterns. Read neighbouring code before proposing.
- **Stay in scope.** Don't demand rewrites or refactors the PR didn't touch. If something broader
  is genuinely worth raising, put it under "Nice to have" or a short "Future work" note.
- **No unexplained jargon.** If a term like idempotent, race condition, memoize, or N+1 appears,
  define it inline in half a sentence the first time.
- **Concrete over abstract.** Any finding without a specific example isn't finished yet.

## Done when

- `CODE_REVIEW.md` exists at the repo root with all the sections above.
- Every finding has: plain-language explanation, concrete example, severity, file and line
  numbers, and before/after code.
- The step-by-step section names a specific file and specific lines and gives paste-ready comment
  text for every comment it asks for.
- `git status` shows no modified source files.
