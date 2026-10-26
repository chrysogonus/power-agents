# Measuring the Verify Gate

The decision log shows how often the gate led to a change. That is not proof
that answers got better: a "Verification: fixed …" line is the agent's own
claim, and turns the gate checked cannot be compared with turns it did not
check. This page describes two ways to measure the effect: a randomized
experiment in everyday use, and a controlled benchmark.

## Field Experiment

### Turning It On

Create `~/.config/power-agents/experiment.json`:

```json
{"arms": {"none": 1, "self": 1, "full": 1}, "audit": 1.0, "capture": false}
```

| Key | Meaning |
| --- | --- |
| `arms` | Relative weights for the three arms. `none`: the turn ends unchecked. `self`: self-check only, even where cross-review is on. `full`: the usual gate, with cross-review where it is enabled. |
| `audit` | Share of `changed` turns (0 to 1) that get a blinded audit. The auditor may be either vendor, so only repositories where cross-review is allowed are audited. |
| `capture` | `true` keeps the texts of each experiment turn for hand-labeling (see [Capture](#capture-and-labeling)). |

Remove the file to stop the experiment. If the file is invalid, the gate checks
every turn as usual, logs the error, and `doctor` reports it.

### What Happens per Turn

1. **Randomization.** Each qualifying turn (see [when a turn
   qualifies](verify-gate.md)) gets an arm at random. The `check` record logs
   `arm`, its probability `p_arm`, whether cross-review could run
   (`review_eligible`), and whether the turn will be audited (`audit`).
2. **Treatment.** The arm decides which checks run. Turns in the `none` arm
   still count as checked, so committing their files later is not checked
   either. This keeps later turns alike in all arms.
3. **Outcome.** When a `changed` turn ends, a background worker measures the
   final state in the same way for every arm:
   - **Blinded audit.** A reviewer receives only the user's request and the
     turn's diff, taken when the turn ended. It sees no transcript and no
     answer, so it cannot tell which arm produced the changes. Claude Code or
     Codex is chosen at random as the auditor. The log keeps its verdict and
     its counts of `high`, `med` and `low` findings. These are null when the
     audit failed, so failures don't count as clean.
   - **Final check.** After the audit, if the repository has a [check
     command](verify-gate.md#per-project-settings), the check runs again. If
     nothing changed since it ran before the self-check, that result is
     reused (`reused`).

   Both may read files the next turn has already changed. `moved` flags this
   on the audit and on a check that ran again.
4. **Follow-up.** When the next prompt arrives, a `next` record logs:
   - whether the prompt reads like a correction (`correction`: words such as
     "wrong", "still fails" or "revert")
   - the seconds since the turn ended (`gap`)

   The next turn's `check` record logs whether that turn changed the same
   files again (`rework`).

Every turn also logs the model, the gate version (`gate`) and the prompt
version (`prompts`). Every verification also logs the tokens it used:
`tokens_in` counts all input, of which `tokens_cache_read` and
`tokens_cache_write` were cache reads and writes, and `tokens_out` counts the
output. Cached input is priced differently, so price the fields separately.
Claude Code can write the reply to its transcript after the gate starts
reading it, so the gate waits up to 3 seconds for the reply; if the reply
never appears, the token fields are null rather than too low. Records share a `turn` id, and the log stays
free of content. The reply to a review logs the tokens spent since the
verify prompt, so the gate's whole cost (`gate_tokens_*`, `gate_seconds` in
the export) includes the response to the review. The auditor's and the
reviewer's own token use is not recorded; their running time is.

### Reading the Results

```bash
python3 ~/.agents/hooks/verify-gate.py stats [--since DAYS]
python3 ~/.agents/hooks/verify-gate.py export [--since DAYS] [--anonymize] > turns.csv
```

- `stats` shows, for each arm, these rates with 95% Wilson intervals:
  - the fix rate
  - the audit-issue rate and high-severity findings per audit
  - the final-check pass rate
  - the correction and rework rates
  - the number of failed audits and the mean cost of the gate

  It also shows the mean verification cost. Last, among turns whose
  self-check found no issues and that got a review, it shows how many had
  review points the agent accepted: how much cross-review adds.
- `export` writes one CSV row per checked turn. `--anonymize` replaces
  repository paths with hashes. Records from before log version 2 have no turn
  id and are matched to their session's latest checked turn.

### Protocol

- **Hypotheses.**
  - H1: `self` leaves fewer audited issues than `none`.
  - H2: `full` leaves fewer than `self`.
  - H3: the cost in seconds and tokens per checked turn, for the gain in
    H1 and H2.
- **Primary outcome.** The audit-issue rate on `changed` turns.
- **Secondary outcomes.** High-severity findings per audit, the final-check
  pass rate, and the correction and rework rates.
- **Analysis.** Compare the arms with their confidence intervals, overall
  and grouped by trigger, auditor and repository. Weight by `1 / p_arm` if
  the weights change during the study.
- **Sample size.** In October 2026 there were about 40 changed turns a day.
  With equal weights and `audit` at 1.0, that gives about 150 audited turns
  per arm in two weeks. That is enough to detect a drop from 40% to 25%
  audited issues at 80% power.

### Threats to Validity

- **One user, not blinded.** The user sees which turns were checked. The
  results also may not hold for other people, repositories or models.
- **An LLM auditor.** An auditor from the same vendor as a reviewer may
  share that reviewer's blind spots. The auditor's vendor is randomized and
  logged, so the results can be grouped by auditor. Calibrate the auditor
  against a hand-labeled sample.
- **Proxy outcomes.** The `correction` regex is crude, so validate it against
  hand labels. Rework can also be planned follow-up work.
- **Overlap.** The audit and the check read the live working tree, and the
  next turn may already be editing it. `moved` flags this; exclude or
  analyze such turns separately. A turn the user interrupts may have no outcome records.
- **Long answers.** Turns that changed no files are not audited. For them,
  only the correction signal measures the outcome.

## Capture and Labeling

With `"capture": true`, each experiment turn keeps its texts in
`~/.cache/verify-gate/capture/<session>.<turn>.jsonl`, readable only by you:
- the request and the first answer
- the verification reply
- the review feedback and the agent's response to it
- the audit
- the first 1,000 characters of the next prompt

These files contain code and conversation. They stay on your machine and are
never deleted automatically.

```bash
python3 ~/.agents/hooks/verify-gate.py export --capture > label.jsonl
```

This writes one JSON object per turn, with empty label fields to fill in by
hand:

| Label | Question it answers |
| --- | --- |
| `label_fix_real` | Was the self-check's fix a real problem? |
| `label_review_points_valid` | Were the review points the agent accepted correct, or did it agree with wrong points? |
| `label_audit_valid` | Is the audit verdict right? |
| `label_correction` | Was the next prompt a correction? |

A labeled sample checks the self-reported numbers, the 96% acceptance rate
of review points, and the audit and correction signals.

## Controlled Benchmark

The [coding evaluations](coding-evaluations.md) run the same task with and
without the gate, in isolated trials checked by tests the agent cannot see:

```bash
make coding-eval CODING_EVAL_ARGS='--agent claude --model SUBJECT_MODEL --gate off on --repeats 2'
```

With `--gate on`, the trial installs the verify gate's hooks (self-check
only, no cross-review) and saves the gate's log records with the trial. Trials
that call a model cost money and run only with `--execute`.
