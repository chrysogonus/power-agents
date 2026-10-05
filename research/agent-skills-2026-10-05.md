# Agent skills and instructions worth collecting

Research snapshot: **2026-10-05**. Scope: coding workflows, engineering quality,
and frontend/design for a personal Codex + Claude Code setup.

Follow-up integration: the owner requested the first-priority skills plus
Anthropic frontend-design with normal automatic discovery. Ten packages are
now in the [skill inventory](../skills/README.md#imported-skills), with pinned
origins and local adaptations in the
[integration snapshot](skill-integration-2026-10-05.json). Their live routing
and effects remain unmeasured; integration is an explicit exception to the
measurement gate proposed in this research. The findings below describe the
research snapshot before that integration.

Start with **Ponytail**, **writing-for-agents**, an explicitly invoked
**grilling** workflow, and whichever of **React performance**, **Postgres**, or
**UI edge-case testing** matches a real project. Treat design systems as a
comparison between alternatives before choosing one.

This is a collection of sources and evaluation candidates. No candidate has
been promoted into `skills/` or installed by this research. Recommendations
below are judgments about potential and fit, not measured improvements in
power-agents. Live model evaluations remain skipped.

## What is attracting attention

These are dated popularity signals, not quality scores. Stars apply to an
entire repository, not to an individual skill. The install figures are the
rounded values displayed by skills.sh; they do not establish unique users,
retention, or successful task completion. A single snapshot cannot establish
GitHub star growth.

The following selected counts came from the
[all-time leaderboard](https://www.skills.sh/) and the site's
[Trending (24h) view](https://www.skills.sh/trending), observed on the research
date. GitHub stars came from each repository's public REST API; exact values,
URLs, and inspected revisions are saved in the
[source snapshot](agent-skills-2026-10-05.json).

| Candidate / collection | Repository stars | All-time installs shown | 24h installs shown | Fit decision |
| --- | ---: | ---: | ---: | --- |
| Ponytail | 155,836 | — | 930 | First comparison against existing simplicity rules |
| Matt Pocock: grill-me | 276,923 | 1.3M | 10.3K | Explicit interview command only |
| Matt Pocock: writing-for-agents | same repository | 365K | — | High relevance to this configuration repo |
| Vercel: React best practices | 31,961 | 772.2K | 2.8K | Strong when a project uses React/Next.js |
| Vercel: composition patterns | same repository | 374.7K | 1.7K | Scoped component refactoring |
| Vercel: web design guidelines | same repository | 701.7K | 3.6K | UI audit with explicit routing |
| Vercel: agent-browser | 43,542 | 1.0M | 10.2K | Tool-dependent browser work |
| Anthropic: frontend-design | 179,763 | 956.4K | 3.6K | Compare against existing design alternatives |
| Taste Skill: design-taste-frontend | 92,790 | 566.1K | 5.4K | Several related skills already available in this session |
| Impeccable | 76,948 | 314.1K | 2.6K | Promising design workflow; inspect executable package |
| Emil: emil-design-eng | 43,610 | 324.6K | 3.7K | Interaction polish rather than another generic builder |
| Supabase: Postgres best practices | 2,700 | 431.7K | 1.6K | Narrow database expertise |
| Superpowers: systematic-debugging | 295,589 | 282.7K | 1.1K | Already available through the session's plugin |
| Caveman | 109,973 | 559.9K | 2.7K | Optional output experiment |
| Uizze: ui-taste | not collected | see listing | 22.4K | Trending watch item; upstream not verified |
| HyperFrames: hyperframes-animation | 57,200 | — | 17.6K | Video-production watch item |

A dash means this report did not collect that metric, not zero. Rankings and
counts can change independently of the pinned source. The broader repository
snapshot also covers Trail of Bits, Addy Osmani, Karpathy-inspired instructions,
GSD, Spec Kit, and BMad.

## Candidates to evaluate first

### 1. Ponytail: preventing unnecessary implementation

Its useful idea is an ordered search for an existing, standard-library, or
native-platform solution before writing custom code. The current skill also
requires tracing the actual code path before simplifying. Its description
covers nearly every coding task, and its mode persists across responses.
[Inspected skill](https://github.com/DietrichGebert/ponytail/blob/cd765194f5e625d2f96e80e63df1c1af0b03705b/skills/ponytail/SKILL.md).

The author reports **54% fewer added lines**, **20% lower cost**, and **27% less
wall-clock time** over 12 feature tasks, Haiku 4.5, four runs per task and arm.
This is an author-run benchmark on one repository and model. Feature scoring
counts diff lines and does not run the application or browser; separate small
security-function tests are executed. Reduced LOC therefore does not establish
feature correctness. Older 80–94% headline results counted single-shot answers
and were acknowledged as inflated by a chatty baseline.
[Method, results, and limitations](https://github.com/DietrichGebert/ponytail/blob/cd765194f5e625d2f96e80e63df1c1af0b03705b/benchmarks/results/2026-06-18-agentic.md).

**Fit:** our global instructions already require simplicity and surgical
changes. Compare the incremental effect before adding another broad skill.
The standalone prompt and the plugin are different packages: upstream's
plugin adds lifecycle hooks and mode handling.
[Package overview](https://github.com/DietrichGebert/ponytail/blob/cd765194f5e625d2f96e80e63df1c1af0b03705b/README.md).

**Test:** implement a native date input, CSV export, and a shared-caller bug fix;
verify acceptance criteria, accessibility, adversarial inputs, added dependencies,
and unnecessary diff size. Include a case where a custom component really is
required. Compare current rules alone, current rules plus a short native/stdlib
preference, and current rules plus Ponytail. Respect existing test conventions;
do not inherit a universal one-test limit.

### 2. writing-for-agents: better instructions and routing

Focuses on trigger wording, context pointers, progressive disclosure, and
checkable completion criteria. It has a supporting `SKILL-MECHANICS.md` file;
collecting only `SKILL.md` loses part of the skill-authoring guidance.
[Skill](https://github.com/mattpocock/skills/blob/4588b32ecab9ecc9fc8cc6b6c5e7d675b6004b0d/skills/productivity/writing-for-agents/SKILL.md),
[mechanics reference](https://github.com/mattpocock/skills/blob/4588b32ecab9ecc9fc8cc6b6c5e7d675b6004b0d/skills/productivity/writing-for-agents/SKILL-MECHANICS.md).

**Fit:** directly relevant to this repo's routing work. Define its ownership
for agent-facing instructions against `prompt-refiner`, `skill-creator`, and
`writing-skills` before promotion.

**Test:** revise an ambiguous description, a sprawling AGENTS.md, and a document
with conditional references. Measure correct loads and completion of the
underlying task, including negative prompts. Fewer words alone is insufficient.

### 3. grilling / grill-me: deliberate idea stress-testing

At the inspected revision, `grill-me` is a seven-line manual entrypoint that
calls `grilling`. The latter interviews in rounds based on decision dependencies,
asks the user for decisions, and delegates discoverable facts to subagents.
It waits for confirmation of shared understanding before acting.
[Entrypoint](https://github.com/mattpocock/skills/blob/4588b32ecab9ecc9fc8cc6b6c5e7d675b6004b0d/skills/productivity/grill-me/SKILL.md),
[actual workflow](https://github.com/mattpocock/skills/blob/4588b32ecab9ecc9fc8cc6b6c5e7d675b6004b0d/skills/productivity/grilling/SKILL.md).

**Fit:** useful when explicitly requested to challenge an idea. Keep it opt-in:
its repeated questioning would conflict with the user's preference for
continuing routine implementation autonomously. Do not import its similarly
named review or handoff skills alongside our existing owners by default.

**Test:** find a genuine missing decision in a project proposal, recommend an
answer, and avoid asking for facts available in the repo. Ordinary bug-fix and
implementation prompts should not start an interview.

### 4. Vercel React performance and composition

`vercel-react-best-practices` prioritizes waterfalls, bundle size, rendering,
and other React/Next.js performance issues. `vercel-composition-patterns`
addresses component APIs and boolean-prop proliferation, with an explicit
React 19-only section. Both rely on their rule files; retain the relevant
complete subtree.
[Performance skill](https://github.com/vercel-labs/agent-skills/blob/063bee94c3f4df8453406c830b0a7df0f2860278/skills/react-best-practices/SKILL.md),
[composition skill](https://github.com/vercel-labs/agent-skills/blob/063bee94c3f4df8453406c830b0a7df0f2860278/skills/composition-patterns/SKILL.md).

**Fit:** load for stack-specific implementation or targeted optimization;
`deep-review` / `review-report` still own general review requests. Check the
project's React version before applying version-specific guidance.

**Test:** remove an actual request waterfall or oversized import and measure
before/after latency or bundle size with unchanged behavior. For composition,
verify existing component states and consumer APIs, including a React 18
negative case.

### 5. Supabase Postgres best practices

Covers query planning, connections, schema design, locking, and row-level
security. The current trigger explicitly includes ordinary schema changes and
Postgres running outside Supabase. Detailed reference files carry the SQL
examples and explanations.
[Skill](https://github.com/supabase/agent-skills/blob/c9be0e931b7930f7d02126d04774d904c381e7d7/skills/supabase-postgres-best-practices/SKILL.md).

**Fit:** stronger domain specificity than another universal coding checklist.
Use only for Postgres; preserve the existing general security-review owner.

**Test:** improve a real query using EXPLAIN evidence; check migration behavior,
locking, and tenant isolation. SQLite and generic security-review requests
should not accidentally load Postgres-specific guidance.

### 6. Emil's break-ui and design engineering

`break-ui` targets realistic worst-case content and explicitly excludes visual
critique and motion review. It can reveal defects hidden by ideal demo data.
`emil-design-eng` provides detailed interaction and motion guidance, but has a
broader scope and a substantial body of instructions.
[Edge-case skill](https://github.com/emilkowalski/skills/blob/e8a175de22ae1e49370fc144c1f3bb9aeedf988d/skills/break-ui/SKILL.md),
[design engineering](https://github.com/emilkowalski/skills/blob/e8a175de22ae1e49370fc144c1f3bb9aeedf988d/skills/emil-design-eng/SKILL.md).

**Fit:** start with `break-ui` because its task and success criteria are easier
to isolate. The session already exposes many broad design skills, while this
repo's canonical inventory contains five different skills.

**Test:** narrow mobile layouts with long unbroken emails, non-Latin text,
empty states, and large counts; compare screenshots and verify that discovered
fixes preserve usable controls. Test reduced-motion and keyboard behavior for
any motion skill. Remove test/demo controls from production output when the
brief requires that.

### 7. Addy Osmani: simplification or measured performance work

`code-simplification` aims for readability while preserving behavior, rather
than minimizing lines. `performance-optimization` starts with measurement and
checks whether the intervention improved the bottleneck.
[Simplification](https://github.com/addyosmani/agent-skills/blob/1401c8b8030e023baeebb31781a6653fe8e93026/skills/code-simplification/SKILL.md),
[performance](https://github.com/addyosmani/agent-skills/blob/1401c8b8030e023baeebb31781a6653fe8e93026/skills/performance-optimization/SKILL.md).

**Fit:** compare simplification against Ponytail as an alternative owner for
that activity. The collection documents a portability gap: some single-skill
installs omit repo-level shared references. Inspect and retain any referenced
resources before vendoring.
[Collection and portability note](https://github.com/addyosmani/agent-skills/blob/1401c8b8030e023baeebb31781a6653fe8e93026/README.md).

**Test:** refactor nested control flow without changing exceptions, ordering,
or side effects. For performance, require a reproducible measurement before
and after. Neither skill should launch an unrequested general review.

## Design alternatives and the broader watchlist

| Source | Potential | Integration decision / limitation |
| --- | --- | --- |
| [Anthropic frontend-design](https://github.com/anthropics/skills/blob/683bc88e56f3e09ba94f7055977f3d3aa499f202/skills/frontend-design/SKILL.md) | Compact, brief-specific visual direction and self-critique | Compare as one primary UI-generation owner. Its own LICENSE.txt is Apache-2.0; other skills in the collection have different terms. |
| [Impeccable](https://github.com/pbakaus/impeccable/blob/87a6ab0c145adb85cbd428a99fa1377305e0818d/README.md) | Design commands, browser iteration, and deterministic defect detectors | Current package includes a launcher and a shipped/downloaded binary; not just Markdown. Compare critique/polish first. Do not create broad command aliases that collide with existing skills. |
| [Taste Skill](https://github.com/leonxlnx/taste-skill/blob/ce26fc25c0e5e8cab638f883de62d9a86ee5e45b/skills/taste-skill/SKILL.md) | Extensive frontend layout and visual-quality guidance | Current main skill has 1,206 lines. Several family members are already available in this session. Evaluate context cost and pick a clear owner rather than stacking similar aesthetics workflows. |
| [Vercel web-design-guidelines](https://github.com/vercel-labs/agent-skills/blob/063bee94c3f4df8453406c830b0a7df0f2860278/skills/web-design-guidelines/SKILL.md) | Focused interface-compliance audit | Fetches live rules at runtime. Pin the fetched guideline revision for reproducible evaluation; route UI audits separately from general code review. |
| [agent-browser](https://github.com/vercel-labs/agent-browser/blob/526157cfd4ec64f45939f9ba0f10d5936aa7ac33/README.md) | Browser inspection and interaction through a dedicated CLI | A tool plus skill; requires its runtime and browser setup. Compare completed flows and locator robustness, not prose quality. |
| [Trail of Bits property-based-testing](https://github.com/trailofbits/skills/blob/82fe8226252622fa807643bdca1710901198553a/plugins/property-based-testing/skills/property-based-testing/SKILL.md) | Domain-wide invariants, roundtrips, shrinking, and tests that expose real faults | Narrower than a general security audit. Keep references and use a project-appropriate test library. Repository license is CC-BY-SA-4.0; retain those terms if imported. |
| [Superpowers](https://github.com/obra/superpowers/blob/8ca22dba9a94f28898bbce59f2537ff4d87c747d/README.md) | Debugging discipline, verification, planning, and task orchestration | Already available as a plugin in this session. Avoid duplicate vendoring. Compare task outcomes and human interruptions before making more workflow steps mandatory. |
| [Karpathy-inspired instructions](https://github.com/multica-ai/andrej-karpathy-skills/blob/2c606141936f1eeef17fa3043a72095b4765b9c2/README.md) | Simple general rules for assumptions, scope, and verification | Already adapted in `instructions/general-global.md`; maintain that source rather than loading a second copy. |
| [Caveman](https://github.com/juliusbrussee/caveman/blob/6571943370f7c9d4de1946481177ee7b306cd8e8/README.md) | Concise output and experiments in context compression | Optional experiment, not a replacement for readable explanations. Its proxy/browser features are separate from the prose skill. Measure retained meaning and completed tasks alongside tokens. |
| [GSD Core](https://github.com/open-gsd/gsd-core/blob/13d37238ba08377929e4850fd6ae4b8db49a22ca/README.md) | Fresh-context subagents and a discuss/plan/execute/verify/ship loop | The [old GSD repository](https://github.com/gsd-build/get-shit-done/blob/bdcaab2c752d9a33a1a1ca9acf3a3c81fb991815/README.md) is archived and redirects here. Current installer performs runtime adaptation; copying commands directly is unsupported. Evaluate in a project first. |
| [GitHub Spec Kit](https://github.com/github/spec-kit/blob/2dda047809dd17fa56200408ce0228a2cfe08be7/README.md) | Durable specifications and project-level development processes | Toolkit with CLI/templates and agent integrations. Compare on a multi-step feature, including process cost; not a drop-in global instruction file. |
| [BMad Method](https://github.com/bmad-code-org/BMAD-METHOD/blob/8f2c13dd0e0073cad84168a679e5c553b2fb30b6/README.md) | Product, architecture, and delivery workflows with durable context | Current setup has module records and supporting tooling. Trial as a project workflow instead of combining it with another complete orchestration system. |
| [HyperFrames](https://github.com/heygen-com/hyperframes/blob/6c353d89c85c0f8a1a3548196e203ee1bd7eec10/README.md) | HTML-based video authoring with domain skills and local rendering | Strong recent install activity, but a separate video-production domain. Requires Node.js 22+ and FFmpeg. Only prioritize if video output is actually wanted. |
| [Uizze ui-taste listing](https://www.skills.sh/site/uizze.sh/ui-taste) | Strong current discovery signal for another design workflow | Listing reports 404.0K installs and optional paid MCP access. Upstream was inaccessible during this pass, so source revision, complete package, and license remain unverified. Watch only. |

The choices in this table are fit judgments. No independent comparative result
was collected for these exact skill revisions unless specifically stated above.
Repository unit tests, demos, install counts, and screenshots do not establish
that adding a skill improves agent performance.

## What the broader evidence says

[SkillsBench 1.1](https://www.skillsbench.ai/blogs/skillsbench-1-1) reports
33.9% → 50.5% mean resolution across its 18 model/harness configurations,
87 tasks, and eight domains. However, 13 tasks have negative average lift, and
invoking a skill does not imply completing the task. These are task-specific
curated packages, not proof that any popular general-purpose skill works here.

[SWE-Skills-Bench](https://arxiv.org/abs/2603.15401v1) tests 49 public software
engineering skills and reports no pass-rate improvement for 39, with only a
small average gain and some substantial token overhead. Its tasks and setup
differ from SkillsBench, so the averages are not interchangeable. Together,
they support checking domain fit and measuring actual outcomes.

[CAVEWOMAN](https://arxiv.org/abs/2606.24083v1) finds that response compression
can reduce cost, while compressing user inputs can increase cost and hurt
accuracy. This does not validate every feature of the current Caveman package.
It supports separating output terseness from input/context compression.

## How a collected candidate becomes a shipped skill

Keep research sources here. Promote only a selected, measured candidate into
`skills/<name>/`, with its complete required resources, upstream revision,
license, and local adaptations recorded in `THIRD_PARTY_NOTICES.md`.

For each candidate, write its intended trigger and exclusions before testing.
General review remains owned by `deep-review` / `review-report`; raw coding
handoff by `coding-agent-brief`; existing prompt refinement by `prompt-refiner`;
and general supported-framework security guidance by `security-best-practices`.
Use explicitly invoked experiments for broad instructions or workflow changes.

A useful comparison keeps the model, runtime, repository revision, prompt,
current global rules, and existing skills fixed. Vary only the candidate.
Use multiple realistic tasks and repeated runs, include negative routing
cases, and measure correctness, regressions, token/cost/time changes, and
human interruptions. Set task-specific acceptance criteria before running.
For visual work, combine functional checks with blinded screenshot comparisons;
for code, execute tests rather than counting lines or trusting the agent's report.

The current `make eval` runner checks prompt-only behavior and routing using
Claude Code plus a separate judge. It cannot yet run repository-editing,
browser, or database effect experiments. Those require an appropriate task
harness; passing routing assertions alone is not a promotion criterion for
these coding skills. Live evaluations were not run during this research.

After a candidate demonstrates its intended benefit without unacceptable
regressions or routing ambiguity, integrate the smallest useful package,
run `./install.sh`, and run `make check`. Keep competing workflow/design
systems as alternatives until the comparison justifies a single owner.

## Reproducibility and collection limits

The JSON snapshot records 19 inspected repositories, their GitHub API metadata,
pinned source commits, and SHA-256 hashes for selected retrieved files. Links
above target inspected commits; moving marketplace entries and live fetched
rules can differ from those sources. Hashes identify the inspected content,
not a package security assessment. Full upstream packages are not vendored.

For an update, revisit the 24h leaderboard, fetch primary repository metadata
and the selected source files, record a new dated snapshot, and compare source
changes before changing the shortlist. No third-party installer was executed
for this research, and no credentials or paid API calls were required.
