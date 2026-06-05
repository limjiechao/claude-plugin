# Critical Review Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the five Critical/High findings from the 3-way codebase review: two guard-hook holes, one settings-write corruption risk, the stale archival docs, and the unenforced runtime-state `.gitignore` invariant.

**Architecture:** Each finding is an independent, file-local fix on branch `claude/cool-clarke-RWgvk`. Guard-hook and settings fixes are test-driven against the repo's existing harness (`bootstrap/tests/`). Doc and `.gitignore` fixes are edits with grep-based verification. No shared state between tasks — they can be done in any order.

**Tech Stack:** bash, `jq`, `grep -E` (ERE), Python 3 `unittest`, JSON.

---

## Context — why this change

The review confirmed five issues that warrant fixing before further work:

- **B-2 (High, confirmed):** `bootstrap/hooks/shell-guard.sh` blocks only short-flag `rm` (`-rf`, `-r `). On Linux, `rm --recursive /path` (GNU long flag) matches no deny pattern, and because the `shell` agent runs `permissionMode: dontAsk` with the hook emitting an explicit `allow`, the delete executes silently. The `settings.snippet.json` deny-list is also short-flag-only.
- **B-3 (High):** `bootstrap/settings_reconcile.py` `_write_json` opens `settings.json` in `"w"` mode, which truncates immediately. A crash mid-`json.dump` (disk full, OOM, signal) leaves a **corrupt/empty `settings.json`** that fails to parse on the next `apply.sh` run.
- **B-1 (Critical, defense-in-depth):** `bootstrap/hooks/git-guard.sh` emits an explicit `allow` for git ops it doesn't recognize, which overrides `settings.json` deny rules. `git push --mirror` is denied in `settings.snippet.json:143` but is *not* in the hook's `deny_patterns`; the hook self-sufficiency should not depend on settings precedence.
- **D-C2/C3 (Critical, docs):** the archival spec and plan under `docs/superpowers/` reference files that never shipped (`install.sh`→`apply.sh`, `export.sh`→`capture.sh`, `docs/adding-tools.md`→`docs/updating-plugin.md`, `docs/install.md`→`docs/local-setup.md`) and place agents/hooks inside the plugin instead of `bootstrap/`.
- **D-C4 (Critical, invariant):** `.gitignore` excludes none of the runtime/account-state paths that CLAUDE.md invariant 4 and `docs/architecture.md` forbid committing.

**Out of scope** (chosen): the Medium/Low items (B-4 `capture.sh` Linux tokenization, B-5/D-I6 dead `statusLine`, B-6 `runner-only` `echo`, D-I1 `test_hooks.sh` missing `-e`, D-I2/I3 idempotency/merge tests, A-1 `waitFor` doc). Do **not** touch them here.

**How to run the test suite** (`docs/testing.md`):
```bash
python3 -m unittest bootstrap.tests.test_settings_reconcile
bash bootstrap/tests/test_hooks.sh
bash bootstrap/tests/test_apply.sh
```

> **Note on plan storage:** plan-mode could only write this file under `/root/.claude/plans/`. As the first execution step, copy it to the repo's canonical location: `docs/superpowers/plans/2026-06-05-critical-review-fixes.md`, then `git add` it with the first commit.

---

## File Structure

| File | Change | Task |
|------|--------|------|
| `bootstrap/hooks/shell-guard.sh` | add 2 long-flag `rm` deny patterns | 1 |
| `bootstrap/settings.snippet.json` | add 2 long-flag `rm` deny-list entries | 1 |
| `bootstrap/tests/test_hooks.sh` | add long-flag-rm and `--mirror` assertions | 1, 2 |
| `bootstrap/hooks/git-guard.sh` | add `--mirror` deny pattern + precedence comment | 2 |
| `bootstrap/settings_reconcile.py` | atomic `_write_json` (tempfile + replace) | 3 |
| `bootstrap/tests/test_settings_reconcile.py` | add write-failure-preserves-original test | 3 |
| `docs/superpowers/specs/2026-06-02-…-design.md` | archival divergence note | 4 |
| `docs/superpowers/plans/2026-06-02-…-truth.md` | archival divergence note | 4 |
| `.gitignore` | runtime/account-state patterns | 5 |

---

## Task 1: Close the `rm --recursive` / `--force` long-flag hole (B-2)

**Files:**
- Modify: `bootstrap/hooks/shell-guard.sh:28` (insert after the `rm -r <dir>` pattern)
- Modify: `bootstrap/settings.snippet.json:96` (insert after `"Bash(rm -f:*)",`)
- Test: `bootstrap/tests/test_hooks.sh` (insert after line 36)

- [ ] **Step 1: Write the failing test.** In `bootstrap/tests/test_hooks.sh`, immediately after the benign-read check (current line 35–36), add:

```bash
# shell-guard: long-form recursive/force deletes blocked (parity with short flags)
for bad in 'rm --recursive /tmp/zzz' 'rm --force /tmp/zzz' 'rm -r --force /tmp/zzz'; do
  [ "$(decision shell-guard.sh "$(jq -nc --arg c "$bad" '{tool_input:{command:$c}}')")" = "block" ] \
    || fail "shell-guard allowed long-form destructive rm: $bad"
done
```

- [ ] **Step 2: Run the test, expect FAIL.**

Run: `bash bootstrap/tests/test_hooks.sh`
Expected: FAIL lines — `shell-guard allowed long-form destructive rm: rm --recursive /tmp/zzz` (and the other two), exit code 1.

- [ ] **Step 3: Add the deny patterns.** In `bootstrap/hooks/shell-guard.sh`, directly after line 28 (`'rm[[:space:]]+-[a-zA-Z]*r[a-zA-Z]*[[:space:]]' ... # rm -r <dir>`), add:

```bash
  'rm[[:space:]]+[^|&;]*--recursive'                                                        # rm --recursive (GNU long flag)
  'rm[[:space:]]+[^|&;]*--force'                                                            # rm --force (GNU long flag)
```

- [ ] **Step 4: Keep the settings deny-list in parity.** In `bootstrap/settings.snippet.json`, directly after line 96 (`"Bash(rm -f:*)",`), add:

```json
      "Bash(rm --recursive:*)",
      "Bash(rm --force:*)",
```

- [ ] **Step 5: Run the test, expect PASS.**

Run: `bash bootstrap/tests/test_hooks.sh`
Expected: `PASS: guard hooks`, exit 0.

- [ ] **Step 6: Validate the edited JSON parses.**

Run: `python3 -m json.tool bootstrap/settings.snippet.json > /dev/null && echo "json ok"`
Expected: `json ok`

- [ ] **Step 7: Commit.**

```bash
git add bootstrap/hooks/shell-guard.sh bootstrap/settings.snippet.json bootstrap/tests/test_hooks.sh
git commit -m "fix(shell-guard): block rm --recursive/--force long flags

Short-flag-only patterns let 'rm --recursive <path>' bypass the denylist
and run under permissionMode: dontAsk. Add long-flag deny patterns to the
hook and matching entries to the settings deny-list, with regression tests."
```

---

## Task 2: Make `git push --mirror` self-sufficient in the hook (B-1)

**Files:**
- Modify: `bootstrap/hooks/git-guard.sh:21` (add to `deny_patterns`) and `:91` (clarify comment)
- Test: `bootstrap/tests/test_hooks.sh:43` (extend the destructive `for bad` loop)

- [ ] **Step 1: Write the failing test.** In `bootstrap/tests/test_hooks.sh`, extend the destructive git-guard loop (current line 43) by adding `"git push --mirror origin"` to the `for bad in …` list:

```bash
for bad in "git restore foo.py" "git reset --hard" "git push --force origin x" "git commit --amend --no-edit" "git branch -D feat" "git push --mirror origin"; do
```

- [ ] **Step 2: Run the test, expect FAIL.**

Run: `bash bootstrap/tests/test_hooks.sh`
Expected: FAIL — `git-guard allowed destructive: git push --mirror origin` (the hook currently returns `ask`, not `block`).

- [ ] **Step 3: Add the deny pattern.** In `bootstrap/hooks/git-guard.sh`, inside `deny_patterns`, directly after line 21 (`'push[^&;|]*(--force|-f|--force-with-lease)' ... # force push`), add:

```bash
  'push[^&;|]*--mirror'                          # mirror push overwrites ALL remote refs
```

- [ ] **Step 4: Document the precedence contract.** In `bootstrap/hooks/git-guard.sh`, replace the comment block at lines 91–92 (`# Allowed: emit an explicit allow decision …`) with:

```bash
# Allowed: emit an explicit allow decision so the command runs even under
# `permissionMode: dontAsk` (a bare `exit 0` would fall through and be denied).
# CONTRACT: because this allow overrides settings.json deny rules, every
# destructive git op MUST be covered by deny_patterns above — do not rely on
# the settings deny-list as the only line of defense for the git agent.
```

- [ ] **Step 5: Run the test, expect PASS.**

Run: `bash bootstrap/tests/test_hooks.sh`
Expected: `PASS: guard hooks`, exit 0.

- [ ] **Step 6: Syntax-check the hook.**

Run: `bash -n bootstrap/hooks/git-guard.sh && echo "syntax ok"`
Expected: `syntax ok`

- [ ] **Step 7: Commit.**

```bash
git add bootstrap/hooks/git-guard.sh bootstrap/tests/test_hooks.sh
git commit -m "fix(git-guard): block 'git push --mirror' in the hook itself

The hook's explicit allow overrides settings deny rules, so --mirror must be
denied in the hook rather than relying on settings precedence. Add the pattern,
a regression test, and a comment documenting the deny_patterns contract."
```

---

## Task 3: Make settings writes atomic (B-3)

**Files:**
- Modify: `bootstrap/settings_reconcile.py:69-71` (`_write_json`)
- Test: `bootstrap/tests/test_settings_reconcile.py` (add a test method)

- [ ] **Step 1: Write the failing test.** In `bootstrap/tests/test_settings_reconcile.py`, add this method to the `SettingsReconcileTests` class (e.g. after `test_replaces_tokens_and_forces_statusline`, before the closing `if __name__`):

```python
    def test_write_failure_preserves_original_file(self):
        from bootstrap import settings_reconcile

        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "settings.json"
            target.write_text(json.dumps({"keep": True}))

            class Unserializable:
                pass

            with self.assertRaises(TypeError):
                settings_reconcile._write_json(target, {"bad": Unserializable()})

            # original must be intact (not truncated) and no temp file left behind
            self.assertEqual(json.loads(target.read_text()), {"keep": True})
            self.assertEqual(list(Path(tmp).glob("*.tmp")), [])
```

- [ ] **Step 2: Run the test, expect FAIL.**

Run: `python3 -m unittest bootstrap.tests.test_settings_reconcile -v`
Expected: `test_write_failure_preserves_original_file` FAILS — the current `open("w")` truncates `target` before `json.dump` raises, so `target` is now empty and `json.loads` raises `JSONDecodeError`.

- [ ] **Step 3: Make `_write_json` atomic.** In `bootstrap/settings_reconcile.py`, replace the function at lines 69–71:

```python
def _write_json(path: Path, value: Any) -> None:
    with path.open("w") as file:
        json.dump(value, file, indent=2)
```

with:

```python
def _write_json(path: Path, value: Any) -> None:
    # Write to a sibling temp file and atomically replace, so an interrupted or
    # failed serialization never leaves a truncated/corrupt target behind.
    tmp = path.with_name(path.name + ".tmp")
    try:
        with tmp.open("w") as file:
            json.dump(value, file, indent=2)
        tmp.replace(path)
    finally:
        if tmp.exists():
            tmp.unlink()
```

- [ ] **Step 4: Run the new test, expect PASS.**

Run: `python3 -m unittest bootstrap.tests.test_settings_reconcile -v`
Expected: all tests PASS, including `test_write_failure_preserves_original_file` (the partial write lands in `.tmp`, gets unlinked by `finally`, and `target` is untouched).

- [ ] **Step 5: Run the apply smoke tests** (they exercise `_write_json` via real `apply.sh` runs):

Run: `bash bootstrap/tests/test_apply.sh`
Expected: `PASS: bootstrap apply smoke tests`

- [ ] **Step 6: Commit.**

```bash
git add bootstrap/settings_reconcile.py bootstrap/tests/test_settings_reconcile.py
git commit -m "fix(settings-reconcile): atomic _write_json to prevent corrupt settings

open('w') truncated settings.json before json.dump completed, so a crash
mid-write left an unparseable file that broke the next apply.sh run. Write to
a sibling .tmp and os.replace; clean up the temp on failure. Add a regression
test that a failed write preserves the original file."
```

---

## Task 4: Add archival divergence notes to the spec and plan (D-C2/C3)

These are historical design documents — **do not rewrite their bodies** (that would falsify the record). Add one prominent note at the top of each mapping the names that changed. No tests apply.

**Files:**
- Modify: `docs/superpowers/specs/2026-06-02-claude-plugin-source-of-truth-design.md` (after line 4, the `**Owner:**` line)
- Modify: `docs/superpowers/plans/2026-06-02-claude-plugin-source-of-truth.md` (after line 2, the `> **For agentic workers:**` line)

- [ ] **Step 1: Annotate the spec.** In the spec, insert a blank line then this block immediately after the `**Owner:** jiechao` line (line 4):

```markdown

> **⚠️ Archival note (added 2026-06-05):** This document records the original
> design intent; the implementation diverged in naming. Read these substitutions
> when following any command or path below:
> `bootstrap/install.sh` → `bootstrap/apply.sh`,
> `scripts/export.sh` → `scripts/capture.sh`,
> `docs/adding-tools.md` → `docs/updating-plugin.md`,
> `docs/install.md` → `docs/local-setup.md`.
> Also: the owner's subagents and guard hooks ship in `bootstrap/agents/` and
> `bootstrap/hooks/` (Layer B), **not** inside the plugin. For current behavior
> see `CLAUDE.md` and `docs/architecture.md`.
```

- [ ] **Step 2: Annotate the plan.** In the plan, insert a blank line then the same block immediately after the `> **For agentic workers:** …` line (line 2):

```markdown

> **⚠️ Archival note (added 2026-06-05):** This historical plan describes files by
> their pre-implementation names. Substitutions: `bootstrap/install.sh` →
> `bootstrap/apply.sh`, `scripts/export.sh` → `scripts/capture.sh`,
> `docs/adding-tools.md` → `docs/updating-plugin.md`, `docs/install.md` →
> `docs/local-setup.md`. Subagents/hooks live in `bootstrap/agents/` and
> `bootstrap/hooks/`, not the plugin. Current behavior: `CLAUDE.md`,
> `docs/architecture.md`.
```

- [ ] **Step 3: Verify the notes landed and name the real files.**

Run: `grep -l "Archival note (added 2026-06-05)" docs/superpowers/specs/*.md docs/superpowers/plans/*.md`
Expected: both file paths printed.

Run: `ls bootstrap/apply.sh scripts/capture.sh docs/updating-plugin.md docs/local-setup.md`
Expected: all four exist (confirms the substitution targets are correct).

- [ ] **Step 4: Commit.**

```bash
git add docs/superpowers/specs/2026-06-02-claude-plugin-source-of-truth-design.md \
        docs/superpowers/plans/2026-06-02-claude-plugin-source-of-truth.md
git commit -m "docs(archival): note install.sh->apply.sh / export.sh->capture.sh divergence

The spec and plan reference pre-implementation filenames and place agents/hooks
in the plugin. Add a divergence note at the top of each rather than rewriting
the historical record."
```

---

## Task 5: Enforce the runtime/account-state invariant in `.gitignore` (D-C4)

**Files:**
- Modify: `.gitignore` (append a section)

- [ ] **Step 1: Append the runtime-state patterns.** Add to the end of `.gitignore`:

```gitignore
# Runtime/account state must never be committed (CLAUDE.md invariant 4,
# docs/architecture.md three-bucket model). Guards against accidental staging
# if tooling ever materializes these into the repo working tree.
history.jsonl
projects/
sessions/
daemon*
telemetry/
ide/
shell-snapshots/
file-history/
plans/
tasks/
```

- [ ] **Step 2: Verify git honors the new patterns.** Confirm representative paths are ignored without affecting tracked files:

Run: `git check-ignore -v history.jsonl projects/x sessions/y telemetry/z`
Expected: each path printed with the matching `.gitignore` rule.

Run: `git status --porcelain`
Expected: no tracked file became deleted/ignored (output unchanged from before the edit aside from the staged `.gitignore`).

- [ ] **Step 3: Commit.**

```bash
git add .gitignore
git commit -m "chore(gitignore): exclude runtime/account state paths

CLAUDE.md invariant 4 forbids committing runtime state but .gitignore did not
enforce it. Add history.jsonl, projects/, sessions/, daemon*, telemetry/, ide/,
shell-snapshots/, file-history/, plans/, tasks/."
```

---

## Final verification

- [ ] **Run the whole suite green:**

```bash
python3 -m unittest bootstrap.tests.test_settings_reconcile
bash bootstrap/tests/test_hooks.sh
bash bootstrap/tests/test_apply.sh
bash bootstrap/tests/test_capture.sh
```
Expected: all PASS.

- [ ] **Confirm no absolute user paths were introduced:**

Run: `grep -rn '/Users/' --include='*.json' --include='*.md' --include='*.sh' bootstrap/ .gitignore docs/ | grep -v 'capture.sh'`
Expected: only documentation/example matches (no new committed absolute paths).

- [ ] **Confirm both edited hooks still parse and the plugin JSON is valid:**

```bash
bash -n bootstrap/hooks/shell-guard.sh && bash -n bootstrap/hooks/git-guard.sh && echo "hooks ok"
python3 -m json.tool bootstrap/settings.snippet.json > /dev/null && echo "snippet ok"
```
Expected: `hooks ok` and `snippet ok`.

- [ ] **Push the branch:**

```bash
git push -u origin claude/cool-clarke-RWgvk
```
(Retry with exponential backoff on network errors only. Do **not** open a PR unless asked.)

---

## Notes for the executor

- TDD order is mandatory for Tasks 1–3: write the test, see it fail for the stated reason, then fix.
- `grep -E` here is ripgrep/POSIX ERE inside the hooks; keep `[^|&;]*` segments anchored to the command so `&&`/`;`/`|` chains can't smuggle a second command past a single pattern.
- Do not "improve" adjacent issues flagged Medium/Low — they were explicitly scoped out. If you spot something new, note it for a follow-up rather than expanding this branch.
