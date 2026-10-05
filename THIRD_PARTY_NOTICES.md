# Third-Party Notices

The root `LICENSE` applies to this repository's original content. The following
components retain their own licenses and attribution.

## Karpathy-Inspired Claude Code Guidelines

Portions of `instructions/general-global.md` are adapted from
[`multica-ai/andrej-karpathy-skills`](https://github.com/multica-ai/andrej-karpathy-skills/blob/main/CLAUDE.md),
authored by `forrestchang` and distributed under the MIT License.

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

All other files, including `SKILL.md`, `LICENSE.txt`, and `agents/openai.yaml`,
remain identical to the pinned upstream content.

The files under `skills/security-best-practices/` are distributed under the
Apache License 2.0. The complete license is preserved at
`skills/security-best-practices/LICENSE.txt`.

## Skills Integrated from the Research Catalog

The following packages were imported from pinned revisions on 2026-10-05.
All have normal automatic discovery, as explicitly requested by the owner.
Live routing and effect evaluations remain unmeasured.

| Local skill | Upstream repository and path | Pinned revision | License |
| --- | --- | --- | --- |
| `ponytail` | [DietrichGebert/ponytail / skills/ponytail](https://github.com/DietrichGebert/ponytail/tree/cd765194f5e625d2f96e80e63df1c1af0b03705b/skills/ponytail) | `cd765194f5e625d2f96e80e63df1c1af0b03705b` | MIT |
| `writing-for-agents` | [mattpocock/skills / skills/productivity/writing-for-agents](https://github.com/mattpocock/skills/tree/4588b32ecab9ecc9fc8cc6b6c5e7d675b6004b0d/skills/productivity/writing-for-agents) | `4588b32ecab9ecc9fc8cc6b6c5e7d675b6004b0d` | MIT |
| `grilling` | [mattpocock/skills / skills/productivity/grilling](https://github.com/mattpocock/skills/tree/4588b32ecab9ecc9fc8cc6b6c5e7d675b6004b0d/skills/productivity/grilling) | `4588b32ecab9ecc9fc8cc6b6c5e7d675b6004b0d` | MIT |
| `vercel-react-best-practices` | [vercel-labs/agent-skills / skills/react-best-practices](https://github.com/vercel-labs/agent-skills/tree/063bee94c3f4df8453406c830b0a7df0f2860278/skills/react-best-practices) | `063bee94c3f4df8453406c830b0a7df0f2860278` | MIT (declared in SKILL.md) |
| `vercel-composition-patterns` | [vercel-labs/agent-skills / skills/composition-patterns](https://github.com/vercel-labs/agent-skills/tree/063bee94c3f4df8453406c830b0a7df0f2860278/skills/composition-patterns) | `063bee94c3f4df8453406c830b0a7df0f2860278` | MIT (declared in SKILL.md) |
| `supabase-postgres-best-practices` | [supabase/agent-skills / skills/supabase-postgres-best-practices](https://github.com/supabase/agent-skills/tree/c9be0e931b7930f7d02126d04774d904c381e7d7/skills/supabase-postgres-best-practices) | `c9be0e931b7930f7d02126d04774d904c381e7d7` | MIT |
| `break-ui` | [emilkowalski/skills / skills/break-ui](https://github.com/emilkowalski/skills/tree/e8a175de22ae1e49370fc144c1f3bb9aeedf988d/skills/break-ui) | `e8a175de22ae1e49370fc144c1f3bb9aeedf988d` | MIT |
| `code-simplification` | [addyosmani/agent-skills / skills/code-simplification](https://github.com/addyosmani/agent-skills/tree/1401c8b8030e023baeebb31781a6653fe8e93026/skills/code-simplification) | `1401c8b8030e023baeebb31781a6653fe8e93026` | MIT |
| `performance-optimization` | [addyosmani/agent-skills / skills/performance-optimization](https://github.com/addyosmani/agent-skills/tree/1401c8b8030e023baeebb31781a6653fe8e93026/skills/performance-optimization) | `1401c8b8030e023baeebb31781a6653fe8e93026` | MIT |
| `frontend-design` | [anthropics/skills / skills/frontend-design](https://github.com/anthropics/skills/tree/683bc88e56f3e09ba94f7055977f3d3aa499f202/skills/frontend-design) | `683bc88e56f3e09ba94f7055977f3d3aa499f202` | Apache-2.0 |

Each local package retains its license at `skills/<name>/LICENSE.txt`.
For Vercel's two skills, upstream declares `license: MIT` in frontmatter but
contains no license file at the pinned revision; the local license files retain
that attribution and reproduce the standard MIT terms without inventing a
copyright statement. Anthropic's frontend skill retains its own Apache-2.0
license; no other Anthropic skill's license is inferred from it.

Runtime resources are retained, including Vercel's compiled guides and rules,
Supabase's references, Matt Pocock's skill mechanics, Emil Kowalski's data
catalog, and Addy Osmani's optimization patterns and performance checklist.
Authoring-only templates, upstream README/changelog files, and build metadata
are omitted. No upstream hooks, installers, or plugin runtimes are imported.

All entrypoints retain upstream instruction content with locally narrowed
routing descriptions, a task/scope boundary, and
`metadata.evaluation-status: unmeasured`. Normal invocation is preserved;
no manual-only flags are added. Local routing fixtures are new and have not
been run against live models. Specific adaptations:

- `ponytail`: Narrowed automatic routing; scoped persistence to the current task; replaced the output cap and one-test/no-framework rules with project-compatible reporting and verification.
- `writing-for-agents`: Narrowed document-authoring routing against prompt-refiner and coding-agent-brief; updated SKILL-MECHANICS.md for Codex invocation policy and normal discovery by default.
- `grilling`: Limited routing to requested interviews; allowed direct factual lookups when subagents are unavailable or unauthorized; made implementation a separate requested step.
- `vercel-react-best-practices`: Separated performance from component API work and general review; repaired three compiled AGENTS.md links to rules/async-defer-await.md, rules/async-cheap-condition-before-await.md, and rules/server-hoist-static-io.md.
- `vercel-composition-patterns`: Separated component API design from React performance and general review; preserved the React 19-only boundary.
- `supabase-postgres-best-practices`: Narrowed routing to Postgres and separated general security guidance and reviews.
- `break-ui`: Separated worst-case content testing from visual design and general review; removed the canned initial response and references to unimported prototype/emil-design-eng/review-animations skills.
- `code-simplification`: Separated working-code refactoring from new functionality and reviews; removed mandatory PR splitting and automatic commits.
- `performance-optimization`: Routed React/Next.js and Postgres-specific work to their owners; removed automatic commits; copied the repo-level performance checklist into local references/ and repaired its entrypoint link and both optimization-patterns.md pointers.
- `frontend-design`: Separated visual design from UI edge-case testing, React performance, and general review.

Trailing whitespace was removed in the imported Vercel compiled guides,
`rules/_sections.md`, and the affected React rule files so repository checks
pass; instruction content in those rules is otherwise unchanged. The exact
file list and adaptation record is preserved in
[the integration snapshot](research/skill-integration-2026-10-05.json).
