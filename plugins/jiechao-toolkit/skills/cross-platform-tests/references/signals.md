# Discriminating portability signals

Concrete patterns to recognise in a test file or PR. Each signal is a *thing
in the code* whose presence means something specific about portability.
This document is organised for **recognition**, not categorisation.

The bar: if you can write a regex that matches the signal, *and* you can
state the interpretation in one sentence, it's specific enough to be useful.
Generic categories like "uses paths" or "uses time" are not signals; they're
buckets to dump speculation into.

## How to use this when auditing

For each finding in your audit, the entry should read:

> *Line N:* `code-from-the-file` — signal Y from `signals.md`. **The
> rationale**: ⟨the *why* — which OS/library/scenario the pattern protects
> against or breaks under, and *why* that mechanism applies⟩. **Recommendation**:
> ⟨specific action, or "no fix needed; this is correct"⟩.

The rationale is load-bearing. "Handled correctly" or "no fix needed" without
naming *what would have happened otherwise* gives the reader a verdict but
not understanding — and verdicts without understanding don't survive
refactors. A reviewer who reads your audit should come away knowing the
mechanism, not just the conclusion.

The two failure modes to avoid:

1. *Verdict without mechanism* — "Filename uses `replaceAll(':', '-')` —
   handled." The reader has no idea what was at risk. If they later refactor
   the filename construction, they may strip the replacement.
2. *Pattern without interpretation* — "Filename construction uses
   `replaceAll(':', '-')` at line N." Pattern noted, but the audit hasn't
   *interpreted* it. Is it good? Bad? Why?

A complete entry names the OS/library/scenario by name. Examples in the
worked-example sections below.

If you can't write the rationale sentence, you probably don't understand
the signal well enough to flag it. Either learn it or skip it. Don't fill
the space with a hedge.

## Signals — high-frequency

### S1. `await tick(N)` immediately followed by an assertion on rendered output

```ts
stdin.write(ENTER)
await tick(60)
expect(stripAnsi(lastFrame() ?? '')).toContain('Loaded')
```

**Meaning.** Race condition. The wait is a constant guess at how long the
async chain (input handler → setState → useEffect → I/O → re-render) takes.
On a fast dev box the constant is enough; on a loaded Ubuntu CI runner it
can be 10x too short.

**Recommendation.** Replace with a polling `waitFor(() => expect(...))`.
A passing fast machine still exits on the first poll iteration; a slow
runner gets up to the timeout.

**Confirming evidence.** If a failure log shows the *previous* state in the
received frame (or a `Loading…` placeholder), the chain hadn't finished —
race confirmed.

### S2. Two consecutive `await tick();` calls

```ts
stdin.write('y')
await tick()
await tick()
expect(...).toContain('Deleted')
```

**Meaning.** The author already met the bug. Double-ticking is a symptomatic
patch — they noticed the test was flaky with one tick, doubled it, called
it good. Stacking ticks doesn't bound the chain; it just doubles the
constant. Almost guaranteed to flake on a slower runner.

**Recommendation.** Same as S1 — `waitFor`. Treat double-tick as
*high-confidence* race evidence, not just a code smell.

### S3. `FOO=1 cmd` in a `package.json` script value

```json
{ "scripts": { "test": "FORCE_COLOR=1 vitest run" } }
```

**Meaning.** POSIX inline env-var syntax. Bash/zsh parses it as
"export then exec"; Windows CMD treats `FORCE_COLOR=1` as the program name
and aborts before `vitest` loads.

**Recommendation.** `cross-env FORCE_COLOR=1 vitest run`, with `cross-env`
as a root devDep.

**Verification trap.** If `FORCE_COLOR` is already set in your shell, this
test passes regardless. To verify, `env -u FORCE_COLOR -u NO_COLOR pnpm
test | cat` — must fail without the fix.

### S4. `.replaceAll(':', '-')` (or similar) in a filename derived from
input

```ts
const filePath = path.join(
  tmpDir,
  `consultation-${envelope.timestamp.replaceAll(':', '-')}.md`,
)
```

**Meaning.** Windows portability defence. NTFS reserves `: < > " / \ | ? *`
in filenames — attempting to create `2025-08-13T09:02:14.md` on Windows
throws `ENOENT` or `EINVAL`. ISO-8601 timestamps always contain `:`, so
*any* test that puts a timestamp into a filename needs this replacement
(or has been silently broken on Windows from the moment it was written).
The replacement is deliberate; the file's author knew NTFS's rules.

**Audit entry — right vs. wrong.** This is the signal where audits most
often note the pattern but fail to name the rationale. Compare:

> ❌ *"Filename construction at lines 132, 142 uses `replaceAll(':', '-')` —
> handled, no fix needed."*
>
> Pattern noted, verdict given, but the reader has no idea what was at
> risk. A refactor that simplifies the filename could strip the
> replacement without anyone noticing.

> ✅ *"Lines 132, 142 — `filePath = ...replaceAll(':', '-')` in a
> timestamp-derived filename. **The rationale**: NTFS reserves `:` (along
> with `< > " / \ | ? *`) in filenames; the ISO-8601 timestamp `2025-08-13
> T09:02:14+0800` would be rejected on Windows without this substitution.
> The replacement is the deliberate defence. **Recommendation**: no fix
> needed; this is correct. If anyone refactors filename construction, the
> replacement must remain."*
>
> Same conclusion, but the reader now knows the *mechanism* (NTFS
> reservation), the *concrete scenario* (timestamp + Windows), and what
> they must preserve through any refactor.

**Recommendation.** No fix needed — this is correct. Flag the *absence* of
this pattern in a similar position. If you see a timestamp going into a
filename without colons stripped, that's the bug.

### S5. `expect(after.mtimeMs).toBe(before.mtimeMs)`

```ts
const before = await fs.stat(filePath)
// ... operation that may or may not write the file ...
const after = await fs.stat(filePath)
expect(after.mtimeMs).toBe(before.mtimeMs)
```

**Meaning.** Asserting against the wrong invariant. mtime resolution varies
wildly:

- FAT/exFAT (rare on CI): 2-second rounding
- ext4 with default inode_size: 1-second rounding
- ext4 with `inode_size>=256`: nanosecond
- NTFS: 100-nanosecond
- APFS: 1-microsecond
- Many Docker overlay filesystems: 1-second rounding

The actual invariant the test wants is *content unchanged*. mtime is a
proxy that can lie either way (advancing on no-op write, or staying
constant on a real write under coarse resolution).

**Recommendation.** Read the file contents before and after, compare as
strings or hashes. `expect(after).toBe(before)`. mtime equality has
exactly one legitimate use: testing the OS's mtime semantics themselves.

### S6. Hardcoded `/tmp/...` or `/var/folders/...` in a test path

```ts
const tmp = '/tmp/my-test'
```

**Meaning.** Not portable. Windows has no `/tmp`.

**Recommendation.** `fs.mkdtemp(path.join(os.tmpdir(), 'my-test-'))`. The
suffix randomisation also avoids parallel-worker collisions.

### S7. `new Date()` / `Date.now()` baked into an assertion as a *string*

```ts
const today = new Date().toISOString().slice(0, 10)
expect(output).toContain(today)
```

**Meaning.** Two problems. (1) The clock runs while the test runs — a test
crossing midnight UTC can produce one day in `today` and another in
`output`. (2) If the production code formats with `toLocaleString` or
similar, the runner's TZ leaks in.

**Recommendation.** Either assert on the *shape* (regex), inject a clock
via dependency injection, use `vi.useFakeTimers()` with
`vi.setSystemTime`, or pin `TZ` at the job level and reformat both sides
with the same explicit timezone.

### S8. `toLocaleString` / `localeCompare` / `Intl.*` *without explicit
locale* in the code under test

```ts
items.sort((a, b) => a.name.localeCompare(b.name))  // locale-default
new Date().toLocaleDateString()                      // locale-default
```

**Meaning.** The result depends on `LANG`/`LC_ALL`. Different runners have
different defaults. Tests asserting on the formatted output will diverge.

**Recommendation.** Pin a locale: `localeCompare(b.name, 'en-US')`,
`toLocaleDateString('en-US', { ... })`. Or pin `LANG=C`/`LC_ALL=C` at
the workflow level, document in a comment near the assertion.

### S9. `process.kill(pid, 0)` (the "ping") or signals like `SIGUSR1`,
`SIGHUP`

```ts
process.kill(pid, 0)        // liveness check
process.kill(pid, 'SIGHUP') // signal
```

**Meaning.** Windows incompatibility. `kill(pid, 0)` throws `EPERM` for
foreign processes on Windows; `SIGUSR1`/`SIGUSR2`/`SIGHUP` don't exist
on Windows at all.

**Recommendation.** For liveness: poll via `child.connected` (if it's a
node child process), or a different mechanism. For signalling: gate the
test with `process.platform !== 'win32'`, or use `SIGTERM`/`SIGKILL`
only.

### S10. `fs.watch(...)` with an assertion on event count

```ts
const events: string[] = []
fs.watch(dir, (event) => events.push(event))
await fs.writeFile(file, 'x')
await tick(100)
expect(events).toHaveLength(1)  // ← Windows often gives 2 or 3
```

**Meaning.** `fs.watch` fires multiple events per write on Windows (the
write often produces both a `rename` and a `change`). On POSIX it's
usually one. Asserting on count is platform-specific.

**Recommendation.** Debounce / deduplicate in the test, or assert on
*the latest event of type X*. Don't assert on count.

### S11. `setRawMode` in a test that uses `ink-testing-library`

```ts
process.stdin.setRawMode(true)  // inside a test
```

**Meaning.** `setRawMode` is a TTY-only method. `ink-testing-library`'s
stdin is a mock, not a TTY, so this throws.

**Recommendation.** Either mock it (`vi.spyOn(process.stdin, 'setRawMode'
).mockImplementation(...)`), or skip the test on non-TTY environments,
or restructure the code under test to skip `setRawMode` when stdin is
not a TTY.

### S12. Reading a file with `\r\n`/`\n` baked into the comparison string

```ts
const content = await fs.readFile(p, 'utf8')
expect(content).toBe('line1\nline2\n')
```

**Meaning.** Possible line-ending leak. If the file was authored on
Windows (or `git config core.autocrlf=true` is in effect on a Windows
checkout), the bytes on disk are `\r\n`. The assertion fails.

**Recommendation.** Either normalise both sides (`.replace(/\r\n/g,
'\n')`), or ensure `.gitattributes` pins LF on this file type
(`* text=auto eol=lf`), or use a substring assertion that doesn't depend
on line endings.

### S13. `import { Foo } from '../Src/foo'` (case-mismatch with on-disk
path)

```ts
import { HistoryApp } from '../Src/history-app'
// while file is actually at 'src/history-app.ts'
```

**Meaning.** macOS and Windows ignore the case mismatch (filesystems are
case-insensitive by default). Linux doesn't. The import resolves
locally; fails in CI.

**Recommendation.** Match the case exactly. Easy to fix once spotted;
easy to miss if you only develop on macOS.

### S14. `&&` / `||` / `;` in `package.json` scripts with non-portable
subcommands

```json
{ "scripts": { "ci": "rm -rf dist && tsc && cp -r assets dist/" } }
```

**Meaning.** `&&` itself works on every shell. The *commands* (`rm -rf`,
`cp -r`) don't exist on Windows CMD. The script breaks on Windows.

**Recommendation.** Either use Node-native equivalents (`rimraf`, `cpy-cli`,
`fs-extra`), or split into JS:

```json
{ "scripts": { "ci": "node scripts/ci.mjs" } }
```

### S15. Tests that depend on `fs.readdir` ordering

```ts
const files = await fs.readdir(dir)
expect(files[0]).toBe('first.txt')
```

**Meaning.** Linux returns inode order (effectively random). macOS returns
sorted-ish. Windows returns alphabetical. Assertions on `files[0]` work
on the developer's box and break on the other OS.

**Recommendation.** Sort before asserting: `expect(files.sort()).toEqual(
['first.txt', 'second.txt'])`. If order matters in the production code,
sort in the production code too.

## Don't flag these — common false positives

These look like portability bugs but aren't. Flagging them dilutes the
signal of real findings. One line each, because that's all they warrant:

- **`path.join(...)`** — the correct pattern. Only flag if the file uses
  string concatenation (`` `${dir}/${file}` ``) *instead of* `path.join`.
- **`fs.mkdtemp(path.join(process.cwd(), 'prefix-'))`** — unconventional
  but portable. If a comment justifies the choice (status-line truncation,
  keeping UI paths short, etc.), engage with the rationale rather than
  re-flagging.
- **`await tick()` between *consecutive* `stdin.write` calls with no
  intervening assertion on rendered output** — legitimate one-macrotask
  yield. The protective `waitFor` is on the subsequent assertion. The
  same goes for `await new Promise((r) => setImmediate(r))` used in the
  same position.
- **`\r` (0x0D) sent via `stdin.write(ENTER)`** — ENTER keycode, not a
  line ending. Portable.
- **`T`, `+0800`-style offsets in filenames** — both legal on every
  modern filesystem (NTFS, APFS, ext4). It's `:` that NTFS reserves; see
  S4.
- **Stdin keycodes (`\x1b[A`, `\x1b[B`, `\x04`, `\x1b`)** — escape-byte
  sequences sent to a virtual stdin in `ink-testing-library`. No OS
  terminal capability involved; byte-identical on every platform.
- **Real `setTimeout(N)` waits where the *thing being tested* is a
  timed behaviour** — animations, debounces, throttles, rate limiters.
  The wait *is* the test. Suggesting fake timers as an alternative is
  fine; calling it a race condition is the false positive.

## Anti-patterns in your audit, not the file

If you find yourself writing any of these phrases, stop:

- *"On older filesystems like FAT..."* — is the file going to run on
  FAT? If not, this is speculation.
- *"In a future version of [library], the default..."* — is there a
  proposed change? If not, this is fantasy.
- *"Out of file scope, but worth noting that the package.json..."* —
  out of scope means out of scope. Cite if relevant to an in-file
  assertion; don't audit it.
- *"This is the canonical failure mode N from the skill..."* — the
  reader doesn't care that the skill organised this finding; they care
  about the file. Cite the file, not the meta.
- *"Pollution on test failure could leave..."* — if the file uses
  `afterEach` cleanup correctly, this is not a real risk. Don't list
  ghosts.

The strongest audit possible is *short, precise, and refuses to fill
empty space*. A 159-line audit with seven concrete findings beats a
338-line audit where five of seven categories have invented risks.

## Recognition exercise — what each of these means at a glance

Skim the snippets; check your reading against the answers below.

```ts
// A
const tick = () => new Promise((r) => setTimeout(r, 60))
stdin.write(ENTER); await tick(); expect(frame).toContain('Done')
```

```ts
// B
const filename = `report-${new Date().toISOString()}.txt`
await fs.writeFile(filename, body)
```

```ts
// C
const out = execSync('grep ERROR app.log').toString()
expect(out).toContain('failed')
```

```json
// D
{ "scripts": { "build": "set NODE_ENV=production && tsc" } }
```

```ts
// E
const files = (await fs.readdir(dir)).filter((f) => f.endsWith('.md'))
expect(files[0]).toBe('2024.md')
```

**Answers:**
- A — S1 (race). Also a candidate for S2 if a sibling test double-ticks.
- B — S4-adjacent. The ISO format includes `:` (e.g., `2024-01-15T10:30:00.000Z`),
  which is NTFS-reserved. Replace `:` with `-` in the filename, or use
  `Date.now()` as a numeric suffix.
- C — Windows incompatibility (no `grep` in CMD). Use Node-native string
  filtering, or rely on a portable wrapper.
- D — Inverse of S3. `set FOO=val && cmd` is CMD-only; POSIX `sh` doesn't
  parse `set` as an assignment. Use `cross-env`.
- E — S15. `readdir` order isn't sorted on Linux. Add `.sort()` before
  asserting.
