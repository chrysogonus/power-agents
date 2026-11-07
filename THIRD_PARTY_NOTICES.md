# Third-Party Notices

The root `LICENSE` applies to this repository's original content. The following
components retain their own licenses and attribution.

## Karpathy-Inspired Claude Code Guidelines

Earlier versions of `instructions/general-global.md` were adapted from
[`multica-ai/andrej-karpathy-skills`](https://github.com/multica-ai/andrej-karpathy-skills/blob/main/CLAUDE.md),
authored by `forrestchang` and distributed under the MIT License. The current
file keeps only two rephrased ideas: stating assumptions instead of guessing,
and mentioning unrelated dead code instead of removing it.

Copyright (c) 2026 forrestchang

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Claude Code Guard Hooks

`hooks/guards/protect-tests.js` and `hooks/guards/protect-secrets.js` are
copied from pinned revisions of
[karanb192/claude-code-hooks](https://github.com/karanb192/claude-code-hooks),
added on 2026-11-03 and distributed under the MIT License, which is preserved
at `hooks/guards/LICENSE`. The upstream plugin manifests, READMEs, and tests are
omitted; `settings/claude/guards-hooks.json` registers the scripts with the
upstream matchers and timeouts (10 seconds is added for `protect-tests`).
`protect-tests.js` is unchanged. `protect-secrets.js` has six local changes,
made on 2026-11-05; reapply them when re-syncing from upstream:

- The `grep-env` rule stays within one command, and no longer counts
  `process.env` or `import.meta.env`.
- A new `read-env` rule blocks other commands that show `.env`: text and binary
  tools such as `sed` and `xxd`, interpreters given it as an argument or in an
  inline, heredoc, or piped script, and any input redirect from it.
- A template name such as `.env.example` exempts only itself in a Bash command,
  instead of skipping every rule when the command ends with one.
- The `xargs-cat-env` rule needs `xargs` as a command, with `cat` in that same
  command or a `.env` path in the command before it, not just a later mention
  anywhere in the line.
- `SINK_PREFIX` matches one wrapper instead of repeating the group, which
  backtracked exponentially on about 30 repeated wrapper words.
- Checks run under a 5-second budget and deny the call when it passes.

| Local file | Upstream path | Pinned revision | License |
| --- | --- | --- | --- |
| `hooks/guards/protect-tests.js` | [karanb192/claude-code-hooks / plugins/protect-tests](https://github.com/karanb192/claude-code-hooks/tree/57a28c7687305e4a9b9dd50490e9b3c552c71ca4/plugins/protect-tests) | `57a28c7687305e4a9b9dd50490e9b3c552c71ca4` | MIT |
| `hooks/guards/protect-secrets.js` | [karanb192/claude-code-hooks / plugins/protect-secrets](https://github.com/karanb192/claude-code-hooks/tree/57a28c7687305e4a9b9dd50490e9b3c552c71ca4/plugins/protect-secrets) | `57a28c7687305e4a9b9dd50490e9b3c552c71ca4` | MIT |

## Contributor Covenant

`CODE_OF_CONDUCT.md` is adapted from the
[Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct.html),
version 2.1, and is distributed under the
[Creative Commons Attribution 4.0 International License](https://creativecommons.org/licenses/by/4.0/).

Copyright (c) 2020 Coraline Ada Ehmke and the Contributor Covenant
contributors.

## Security Best Practices Skill

Upstream repository: [`openai/skills`](https://github.com/openai/skills).
Upstream path: `skills/.curated/security-best-practices`.
Pinned content revision:
[`5c8f1e26803bcfaffeceef1e7accbcf7e388417a`](https://github.com/openai/skills/tree/5c8f1e26803bcfaffeceef1e7accbcf7e388417a/skills/.curated/security-best-practices).

All 13 files in the initial local import (`2c8bf4514948c813fc0cec0525a2a8307fd5bc82`)
match that upstream revision byte for byte. This is the commit that introduced
the upstream skill; its subtree is also unchanged at upstream `main` revision
`49f948faa9258a0c61caceaf225e179651397431`, checked on 2026-10-05. The historical
checkout used for the import was not recorded; the pinned revision identifies
the matching source content.

Local commit `5ec295f71a8a31bdc58ca833d86ad8ed3c436b6c` made only these formatting
changes under `references/`:

- `javascript-express-web-server-security.md`: removed one trailing space from
  the bearer-token CSRF note (line 379).
- `javascript-general-web-frontend-security.md`: removed one trailing space
  from the JS-XSS-002 severity line (line 185).
- `python-django-web-server-security.md`: removed one trailing space from the
  DJANGO-CSP-001 severity line (line 644).
- `javascript-typescript-react-web-frontend-security.md`: collapsed the
  multiline title of reference `[16]` to `draft-ietf-oauth-browser-based-apps-26`
  on a single line (line 979), removing 52 bytes of whitespace. The URL and
  title text are unchanged.

All other imported files, including `SKILL.md`, `LICENSE.txt`, and
`agents/openai.yaml`, remain identical to the pinned upstream content.
`evals/evals.json` is a local addition, not part of the upstream skill.

The files under `skills/security-best-practices/` are distributed under the
Apache License 2.0. The complete license is preserved at
`skills/security-best-practices/LICENSE.txt`.

## Skills Integrated from the Research Catalog

The following packages were imported from pinned revisions on 2026-10-05;
`ponytail` was re-synced to Ponytail 5 on 2026-10-24, and
`test-driven-development` and `systematic-debugging` were added on 2026-11-01, and
`grilling`, `code-simplification`, and `performance-optimization` were re-synced
on 2026-11-01. `agent-browser`, `improve-codebase-architecture`, `handoff`,
`triage`, `domain-modeling`, `codebase-design`, and `design-taste-frontend` were
added on 2026-11-03, and `using-git-worktrees`, `finishing-a-development-branch`,
and `claude-skill-creator` were added on 2026-11-04.
All have normal automatic discovery, as explicitly requested by the owner.
Live routing and effect evaluations remain unmeasured.

| Local skill | Upstream repository and path | Pinned revision | License |
| --- | --- | --- | --- |
| `ponytail` | [DietrichGebert/ponytail / skills/ponytail](https://github.com/DietrichGebert/ponytail/tree/09c434ab73ca43761c5d8b0c5d341926c2fba710/skills/ponytail) | `09c434ab73ca43761c5d8b0c5d341926c2fba710` | MIT |
| `writing-for-agents` | [mattpocock/skills / skills/productivity/writing-for-agents](https://github.com/mattpocock/skills/tree/4588b32ecab9ecc9fc8cc6b6c5e7d675b6004b0d/skills/productivity/writing-for-agents) | `4588b32ecab9ecc9fc8cc6b6c5e7d675b6004b0d` | MIT |
| `grilling` | [mattpocock/skills / skills/productivity/grilling](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/productivity/grilling) | `4ae2317ddb22b046e26455e4f9c9b3aaaf62212d` | MIT |
| `vercel-react-best-practices` | [vercel-labs/agent-skills / skills/react-best-practices](https://github.com/vercel-labs/agent-skills/tree/063bee94c3f4df8453406c830b0a7df0f2860278/skills/react-best-practices) | `063bee94c3f4df8453406c830b0a7df0f2860278` | MIT (declared in SKILL.md) |
| `vercel-composition-patterns` | [vercel-labs/agent-skills / skills/composition-patterns](https://github.com/vercel-labs/agent-skills/tree/063bee94c3f4df8453406c830b0a7df0f2860278/skills/composition-patterns) | `063bee94c3f4df8453406c830b0a7df0f2860278` | MIT (declared in SKILL.md) |
| `supabase-postgres-best-practices` | [supabase/agent-skills / skills/supabase-postgres-best-practices](https://github.com/supabase/agent-skills/tree/c9be0e931b7930f7d02126d04774d904c381e7d7/skills/supabase-postgres-best-practices) | `c9be0e931b7930f7d02126d04774d904c381e7d7` | MIT |
| `break-ui` | [emilkowalski/skills / skills/break-ui](https://github.com/emilkowalski/skills/tree/e8a175de22ae1e49370fc144c1f3bb9aeedf988d/skills/break-ui) | `e8a175de22ae1e49370fc144c1f3bb9aeedf988d` | MIT |
| `code-simplification` | [addyosmani/agent-skills / skills/code-simplification](https://github.com/addyosmani/agent-skills/tree/8bfcc1f9916f2eea55494d8c1fa7f4bde867dd9e/skills/code-simplification) | `8bfcc1f9916f2eea55494d8c1fa7f4bde867dd9e` | MIT |
| `performance-optimization` | [addyosmani/agent-skills / skills/performance-optimization](https://github.com/addyosmani/agent-skills/tree/8bfcc1f9916f2eea55494d8c1fa7f4bde867dd9e/skills/performance-optimization) | `8bfcc1f9916f2eea55494d8c1fa7f4bde867dd9e` | MIT |
| `test-driven-development` | [obra/superpowers / skills/test-driven-development](https://github.com/obra/superpowers/tree/2ce8aa15d05bd57213e6f746f953aafb7ded7a8b/skills/test-driven-development) | `2ce8aa15d05bd57213e6f746f953aafb7ded7a8b` | MIT |
| `systematic-debugging` | [obra/superpowers / skills/systematic-debugging](https://github.com/obra/superpowers/tree/2ce8aa15d05bd57213e6f746f953aafb7ded7a8b/skills/systematic-debugging) | `2ce8aa15d05bd57213e6f746f953aafb7ded7a8b` | MIT |
| `frontend-design` | [anthropics/skills / skills/frontend-design](https://github.com/anthropics/skills/tree/683bc88e56f3e09ba94f7055977f3d3aa499f202/skills/frontend-design) | `683bc88e56f3e09ba94f7055977f3d3aa499f202` | Apache-2.0 |
| `agent-browser` | [vercel-labs/agent-browser / skills/agent-browser](https://github.com/vercel-labs/agent-browser/tree/32a2b0b2f96217867846d80083fd12980d783d26/skills/agent-browser) | `32a2b0b2f96217867846d80083fd12980d783d26` | Apache-2.0 |
| `improve-codebase-architecture` | [mattpocock/skills / skills/engineering/improve-codebase-architecture](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/improve-codebase-architecture) | `4ae2317ddb22b046e26455e4f9c9b3aaaf62212d` | MIT |
| `handoff` | [mattpocock/skills / skills/productivity/handoff](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/productivity/handoff) | `4ae2317ddb22b046e26455e4f9c9b3aaaf62212d` | MIT |
| `triage` | [mattpocock/skills / skills/engineering/triage](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/triage) | `4ae2317ddb22b046e26455e4f9c9b3aaaf62212d` | MIT |
| `domain-modeling` | [mattpocock/skills / skills/engineering/domain-modeling](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/domain-modeling) | `4ae2317ddb22b046e26455e4f9c9b3aaaf62212d` | MIT |
| `codebase-design` | [mattpocock/skills / skills/engineering/codebase-design](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/codebase-design) | `4ae2317ddb22b046e26455e4f9c9b3aaaf62212d` | MIT |
| `design-taste-frontend` | [leonxlnx/taste-skill / skills/taste-skill](https://github.com/leonxlnx/taste-skill/tree/12af471f627f866411b4bd785b19646d3672784c/skills/taste-skill) | `12af471f627f866411b4bd785b19646d3672784c` | MIT |
| `using-git-worktrees` | [obra/superpowers / skills/using-git-worktrees](https://github.com/obra/superpowers/tree/22f0b463e7a5e579904dd6211a520321035526f7/skills/using-git-worktrees) | `22f0b463e7a5e579904dd6211a520321035526f7` | MIT |
| `finishing-a-development-branch` | [obra/superpowers / skills/finishing-a-development-branch](https://github.com/obra/superpowers/tree/22f0b463e7a5e579904dd6211a520321035526f7/skills/finishing-a-development-branch) | `22f0b463e7a5e579904dd6211a520321035526f7` | MIT |
| `claude-skill-creator` | [anthropics/skills / skills/skill-creator](https://github.com/anthropics/skills/tree/ca45fc496a3436251f191354091d557da31c15b5/skills/skill-creator) | `ca45fc496a3436251f191354091d557da31c15b5` | Apache-2.0 |

Each local package retains its license at `skills/<name>/LICENSE.txt`.
For Vercel's two skills, upstream declares `license: MIT` in frontmatter but
contains no license file at the pinned revision; the local license files retain
that attribution and reproduce the standard MIT terms without inventing a
copyright statement. Anthropic's frontend skill retains its own Apache-2.0
license; no other Anthropic skill's license is inferred from it, and
`claude-skill-creator` retains the Apache-2.0 `LICENSE.txt` shipped in its own
upstream directory. The
`agent-browser` license is the Apache-2.0 file at the root of
vercel-labs/agent-browser, and the `design-taste-frontend` license is the MIT
file at the root of leonxlnx/taste-skill.

Runtime resources are retained, including Vercel's compiled guides and rules,
Supabase's references, Matt Pocock's skill mechanics, Emil Kowalski's data
catalog, Addy Osmani's optimization patterns and performance checklist, and
superpowers' testing and debugging references and `find-polluter.sh`, Matt
Pocock's architecture, triage, and domain-modeling references, taste-skill's
scripts, assets, library, and references, and skill-creator's agents, scripts,
eval viewer, assets, and schema reference. Authoring-only templates, superpowers'
creation log and pressure-test scenarios, taste-skill's README and comparative
evals, upstream README/changelog files, and build metadata are omitted.
`agent-browser` is the upstream discovery stub only; its workflow content is
served by the separately installed `agent-browser` CLI, which this repository
does not install. No upstream hooks, installers, or plugin runtimes are imported.

All entrypoints retain upstream instruction content with locally narrowed
routing descriptions, a task/scope boundary, and
`metadata.evaluation-status: unmeasured`. Normal invocation is preserved;
no manual-only flags are added. Local routing fixtures are new and have not
been run against live models. Specific adaptations:

- `ponytail`: Re-synced to Ponytail 5 on 2026-10-24. Narrowed automatic routing; scoped persistence to the current task (no session mode or `off` level); replaced the one-test/assert self-check rule with project-compatible verification; kept the reply-ending skipped/risk lines inside project-compatible reporting.
- `writing-for-agents`: Narrowed document-authoring routing against prompt-refiner; updated SKILL-MECHANICS.md for Codex invocation policy and normal discovery by default.
- `grilling`: Limited routing to requested interviews; allowed direct factual lookups when subagents are unavailable or unauthorized; made implementation a separate requested step.
- `vercel-react-best-practices`: Separated performance from component API work and general review; repaired three compiled AGENTS.md links to rules/async-defer-await.md, rules/async-cheap-condition-before-await.md, and rules/server-hoist-static-io.md.
- `vercel-composition-patterns`: Separated component API design from React performance and general review; preserved the React 19-only boundary.
- `supabase-postgres-best-practices`: Narrowed routing to Postgres and separated general security guidance and reviews.
- `break-ui`: Separated worst-case content testing from visual design and general review; removed the canned initial response and references to unimported prototype/emil-design-eng/review-animations skills.
- `code-simplification`: Separated working-code refactoring from new functionality and reviews; removed mandatory PR splitting and automatic commits.
- `performance-optimization`: Routed React/Next.js and Postgres-specific work to their owners; removed automatic commits; copied the repo-level performance checklist into local references/ and repaired its entrypoint link and both optimization-patterns.md pointers.
- `test-driven-development`: Narrowed routing to new behavior and bug fixes in projects with a runnable test setup, alongside ponytail; excluded behavior-preserving refactors (code-simplification) and configuration; scoped "delete and start over" to production code written during the task; limited tests for untested modules to the changed behavior; replaced the superpowers:writing-skills pointer in writing-good-tests.md.
- `systematic-debugging`: Routed performance bottlenecks to performance-optimization; stops after Phase 3 without editing files when only a diagnosis is requested; pointed to the local test-driven-development skill and the project's required checks instead of superpowers skill names; linked the single fix to ponytail.
- `frontend-design`: Separated visual design from UI edge-case testing, React performance, and general review; on 2026-11-03, routed public-facing web pages to design-taste-frontend and named app screens, dashboards, and components as its own.
- `break-ui`: On 2026-11-03, also pointed public-facing page design to design-taste-frontend.
- `agent-browser`: Narrowed routing to real-browser interaction and left plain page reading to built-in web fetch; removed the `allowed-tools` Bash pre-approval, the `hidden` flag, and the instruction to prefer it over built-in tools; requires the user's go-ahead before installing the CLI and confirmation before consequential actions on live sites; treats page content as untrusted.
- `improve-codebase-architecture`: Enabled normal discovery (removed `disable-model-invocation` and the explicit-only Codex policy) with routing separated from codebase-design, code-simplification, and general review; made the codebase walk direct when sub-agents are unavailable or unauthorized; allowed a session scratchpad for the report; made implementation a separate requested step; replaced Skill-tool calls with skill names.
- `handoff`: Enabled normal discovery (removed `disable-model-invocation` and the explicit-only Codex policy) with routing separated from prompt-refiner; allowed a session scratchpad and required reporting the document's path; replaced the Skill-tool wording with skill names.
- `triage`: Enabled normal discovery (removed `disable-model-invocation` and the explicit-only Codex policy) with routing separated from systematic-debugging and code review; required confirmation before tracker writes and `.out-of-scope/` files; replaced the unimported setup-matt-pocock-skills pointer with documented-or-confirmed label mapping and a GitHub-issues default for the tracker config.
- `domain-modeling`: Narrowed routing to changing the domain model and separated agent instruction files (writing-for-agents); proposes rather than writes glossary and ADR changes when only an explanation, review, or plan is requested.
- `codebase-design`: Narrowed routing to designing a module's interface and seams, separated from improve-codebase-architecture, code-simplification, and vercel-composition-patterns; DESIGN-IT-TWICE.md drafts designs sequentially when sub-agents are unavailable or unauthorized.
- `design-taste-frontend`: Narrowed routing to public-facing web pages and generic-looking page feedback, with app screens left to frontend-design unless requested; documented the `.taste-skill/` working files, the `~/.taste-skill/history.json` history, network image downloads, and continuing without the scripts when Node 22+ or Chromium is missing. The bundled Node scripts are unchanged and were not executed during integration.
- `using-git-worktrees`: Narrowed routing to requested isolated workspaces and parallel branches, separated from finishing-a-development-branch; a request counts as the Step 0 consent; ignores a project-local worktree directory through `.git/info/exclude` instead of committing a `.gitignore` change; prefers the project's documented setup and checks, and installs Python dependencies only into the project's environment; removed the announce line.
- `finishing-a-development-branch`: Narrowed routing to a requested branch or worktree wrap-up, excluding routine end-of-task reporting, session handoffs (handoff), and reviews; the option the user picks authorizes only that merge or push; runs the project's required checks; names using-git-worktrees as the owner of `.worktrees/` cleanup; removed the announce line.
- `claude-skill-creator`: Renamed from `skill-creator` so it does not shadow the skill-creator bundled with Codex; narrowed routing to building or improving skills through Claude Code test runs, benchmarks, and description optimization, separated from writing-for-agents; repository skill conventions and routing boundaries replace the "pushy" description advice; workspaces go to a scratchpad or temporary directory instead of beside the skill; paid runs require explicit approval of their size and model; documents that `scripts.run_eval` writes a temporary `.claude/commands/` file, that the eval viewer terminates any process on its port, and that its pages load Google Fonts and SheetJS from CDNs. The bundled scripts are unchanged apart from trailing-whitespace removal on one line each of `scripts/quick_validate.py` and `scripts/improve_description.py` (the second inside a prompt string), and were not executed during integration.
- `writing-for-agents`: On 2026-11-04, pointed skill test runs, benchmarks, and description-trigger optimization to claude-skill-creator.

Trailing whitespace was removed in the imported Vercel compiled guides,
`rules/_sections.md`, and the affected React rule files so repository checks
pass; instruction content in those rules is otherwise unchanged. Each skill's
pinned revision, upstream path, adaptations, and whitespace-normalized files
are recorded in
[the integration snapshot](research/skill-integration-2026-10-05.json); it does
not list every imported file.
