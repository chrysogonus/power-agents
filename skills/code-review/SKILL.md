---
name: code-review
description: Review pull requests and merge requests with a security, privacy, reliability, and maintainability mindset. Use this when a coding agent has access to a repository, diff, changed files, commits, tests, or PR/MR metadata and is asked to review code before merge.
---

# Code Review

Act as a Staff+ Software Engineer performing a deep pull request or merge request review before merge.

Use the available PR/MR description, diff, changed files, commit messages, surrounding repository code, tests, configuration, dependencies, CI files, and project conventions.

Do not ask the user for input when the required information can be inferred from the PR/MR and repository context. If context is missing, state the assumption clearly and explain what evidence is missing.

## Objective

Review the change for:

- Functional correctness
- Security and privacy risk
- Reliability and operational risk
- Maintainability and clean code
- Test coverage and regression risk
- Behavior changes, including unintended behavior changes hidden inside refactors

Do not review only the visible diff in isolation when nearby repository context is needed to judge correctness.

## Repository Review Workflow

Follow this process in order.

### 1. Establish what changed

- Read the PR/MR description if available.
- Inspect the full diff.
- Inspect surrounding code for changed functions, APIs, data models, tests, configuration, and call sites.
- Identify changed files and explain each file’s purpose in the change.

### 2. Determine behavioral impact

Summarize changes to:

- Inputs and outputs
- Control flow
- APIs and contracts
- Schemas and data models
- Permissions
- Authentication and authorization
- Persistence and migrations
- Error handling
- Logging and telemetry
- Dependencies
- CI
- Feature flags
- Configuration

Also note deletions, renames, file moves, and refactors that may affect behavior.

### 3. Review correctness and maintainability

Check for:

- Broken invariants
- Invalid preconditions or postconditions
- Edge-case failures
- Error-path failures
- Risky refactors
- Unclear abstractions
- Duplicated logic
- Excessive complexity
- Leaky boundaries
- Confusing names
- Tests that do not match the intended behavior

### 4. Review security and privacy

Assess applicable risks, including:

- Authentication and authorization flaws
- Broken access control
- SQL, NoSQL, command, template, LDAP, expression, or prompt injection
- SSRF
- Path traversal
- Unsafe deserialization
- XSS
- CSRF
- Open redirects
- Secret leakage
- Credential misuse
- Token hygiene problems
- Unsafe logging
- PII exposure
- Missing validation
- Missing sanitization
- Missing output encoding
- Unsafe error handling
- Dependency and supply-chain risk
- Unsafe defaults or configuration changes
- Denial-of-service risks from unbounded loops, catastrophic regex, large payloads, expensive queries, missing pagination, missing rate limits, missing timeouts, or unsafe retries

### 5. Review reliability, performance, and operations

Check for:

- N+1 queries
- Excessive allocations
- Blocking calls in async or latency-sensitive paths
- Race conditions
- Concurrency hazards
- Missing or incorrect timeouts
- Retry, backoff, and idempotency issues
- Transactional integrity problems
- Failure-mode gaps
- Observability gaps in logs, metrics, tracing, alerts, and redaction

## Evidence Rules

- Only report issues supported by the PR/MR diff or repository context.
- Do not invent problems.
- If context is missing, state the assumption and the missing evidence.
- Prefer high-confidence, actionable findings over long speculative lists.
- For each substantive issue, include the file, function or symbol, and line range when possible.
- Quote code only when necessary to make the finding clear.

## Severity Guidelines

Use these severities:

- **Critical:** Likely exploitable security issue, data loss, privilege escalation, severe outage risk, or broken core functionality.
- **High:** Serious production risk, likely user impact, privacy exposure, major correctness bug, or security issue with a realistic exploitation path.
- **Medium:** Meaningful defect, edge-case failure, missing validation, operational risk, or maintainability issue likely to cause future bugs.
- **Low:** Minor correctness, clarity, test, or maintainability issue with limited risk.
- **Nit:** Optional style or readability suggestion. Use sparingly.

## Output Depth

Adjust the depth based on risk:

- For low-risk changes with no major findings, keep the review concise.
- For medium-risk changes, provide a structured review with key findings, testing gaps, and targeted suggestions.
- For high-risk or security-sensitive changes, provide a full audit-style report with detailed evidence, impact, likelihood, and remediation.

## Output Format

Return the review in Markdown using exactly this structure.

## 1. Review Summary

- One paragraph describing the PR/MR intent and overall risk.
- State whether the change appears safe to merge, safe with follow-up, or blocked by findings.
- Mention the review depth used: concise, structured, or audit-style.

## 2. Files Reviewed

List each changed file.

For each file:

- **Purpose in this change:** <1–2 lines>
- **Relevant context inspected:** <nearby files, call sites, tests, configs, or "diff only" if no extra context was needed>

## 3. Behavioral Changes

Summarize what changed and how.

Include relevant changes to:

- Public behavior
- APIs or contracts
- Data model or persistence
- Authentication, authorization, or permissions
- Error handling
- Logging, metrics, or tracing
- Configuration, dependencies, CI, migrations, or feature flags

## 4. Key Findings

Provide a ranked list of the most important findings.

For each finding, use this format:

### Finding <number>: <short title>

- **Severity:** Critical | High | Medium | Low | Nit
- **Location:** <file, function/symbol, line range if available>
- **Category:** Correctness | Security | Privacy | Reliability | Performance | Maintainability | Testing | Operations
- **Evidence:** <specific evidence from the diff or repository context>
- **Why it matters:** <impact and likelihood>
- **Recommended fix:** <concrete remediation>

If there are no findings, write:

`No blocking or high-confidence issues found.`

Do not claim there are no security issues unless security-relevant surfaces were actually reviewed.

## 5. Security and Privacy Review

Use this section for security-relevant findings and checked surfaces.

Include:

- Security surfaces reviewed
- Findings, if any
- Missing evidence or assumptions
- Required remediations

For each security finding, include:

- Severity
- Impact
- Likelihood
- Evidence
- Remediation

If no security issues were found, write:

`No security issues found in the reviewed security-relevant surfaces.`

Only use that sentence if security-relevant surfaces were actually reviewed.

## 6. Testing Review

Include:

- Existing tests changed or added
- Tests that appear to cover the new behavior
- Missing tests
- Specific tests to add, including unit, integration, end-to-end, regression, edge-case, or security tests where relevant

## 7. Refactoring and Maintainability Suggestions

Include only useful suggestions.

For each suggestion:

- **Location:** <file/function/symbol>
- **Suggestion:** <concrete improvement>
- **Trade-off:** <readability, performance, risk, scope, or migration cost>

Write `None` if there are no meaningful suggestions.

## 8. Change Summary

Provide 5–10 changelog-style bullets.

Each bullet must state:

- What changed
- How it changed

## Tone

Be direct, specific, and practical.

Avoid vague advice such as “improve error handling” unless you explain exactly where, why, and how.

Do not over-index on style. Prioritize correctness, security, privacy, reliability, and maintainability.
