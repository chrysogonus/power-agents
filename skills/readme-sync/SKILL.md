---
name: readme-sync
description: 'Generate or update the root README.md to reflect the current state of the codebase. Use when: creating a README from scratch, refreshing an outdated README, "write a README", "update README", "what should the README say". Reads docs/ or doc/ first, then source files for details. Do not use for other documentation, such as runbooks, API references, architecture docs, or onboarding guides.'
argument-hint: 'Optional: specific sections to focus on (e.g., "installation and usage only")'
---

# README Sync Skill

## Purpose

Create or update the root `README.md` so it accurately reflects the current codebase. The README should be useful to a developer seeing the project for the first time.

## When to Use

- No `README.md` exists yet
- The existing README is outdated after code changes
- A project has been restructured and the README no longer matches
- Adding a new service, feature, or configuration that should be documented

## Procedure

### 1. Check for an Existing README

- Check if `README.md` exists at the project root.
- If it exists, read it fully and note what sections are present and what is stale or missing.
- If it does not exist, proceed to create one from scratch.

### 2. Read Documentation Sources (Priority Order)

Read available documentation in this order, stopping when you have sufficient context:

1. **`doc/`** — Read all files in `doc/` (or `docs/`). These are the authoritative source of intent, architecture decisions, and design.
2. **Config and manifest files** — `package.json`, `pyproject.toml`, `setup.py`, `setup.cfg`, `Cargo.toml`, `go.mod`, `requirements.txt` — for project name, description, version, dependencies, and scripts.
3. **`Makefile`** — Extract available targets and their purpose (build, test, run commands).
4. **`docker-compose.yml`** — Identify services, ports, and dependencies.
5. **`Dockerfile`(s)** — Understand how the app is containerized, entry points, exposed ports.

### 3. Read Source Code for Details

For each top-level directory or entry point:

- **`main.py` / `index.ts` / `app.py` / `server.js`** — Read the entry point to understand startup, routes, and high-level structure.
- **`README`-adjacent files** — `.env.example`, `config/`, `scripts/` — capture required env vars and setup steps.
- Read additional source files only to resolve gaps (e.g., unclear API, missing env var list, unclear architecture).

Do NOT read test files unless the README specifically needs a "Running Tests" section.

### 4. Draft or Update the README

Write or revise `README.md` using this structure (omit sections that have no relevant content):

```markdown
# <Project Name>

<1-3 sentence description of what the project does and who it is for>

## Architecture / Overview (optional)

<High-level diagram or bullet list of components, only if project has multiple services>

## Prerequisites

<Runtime versions, tools, environment requirements>

## Installation

<Steps to clone and set up the project>

## Configuration

<Environment variables table: variable | required | description | example>

## Running the Project

<Commands to start the project — prefer Makefile targets if they exist>

## Development

<How to run in dev mode, hot reload, debug flags>

## Running Tests

<Test command and how to interpret results>

## Project Structure

<Brief map of the top-level directories and their role>

## API Reference (optional)

<Endpoints, inputs, outputs — only if this is a service with a public API>

## Contributing (optional)

<Conventions, branch naming, PR process — only if relevant>
```

**Tone and style rules:**
- Write for a developer seeing the project for the first time.
- Be concise — prefer bullet points and code blocks over prose.
- Every command must be copy-pasteable and correct.
- Do not include placeholder content (`<your value here>`) without a real example alongside it.
- If a section would be empty or trivial, omit it. CLI tools and libraries usually need no Configuration, Docker, or API Reference section.

### 5. Write the File

- If creating: write `README.md` to the project root.
- If updating: make targeted edits — preserve sections that are still accurate, rewrite stale sections, add new sections for new features. Do not rewrite a good README from scratch.

### 6. Verify

After writing, re-read the `README.md` and confirm:
- [ ] Project name and description are correct.
- [ ] All commands in the README are present in `Makefile`, `package.json` scripts, or source — no invented commands. Run the ones that are quick and side-effect free (such as `--help` or a lint target); report the rest as checked against files only.
- [ ] All referenced environment variables exist in `.env.example` or source code.
- [ ] No placeholder text remains unresolved.
- [ ] Sections that don't apply to this project are omitted.

## Quality Gates

A README is complete when:
- [ ] A new developer can clone, configure, and run the project using only the README.
- [ ] All commands are verified against actual project files.
- [ ] The architecture/structure section reflects the current directory layout.
- [ ] No stale information from the old README remains.
