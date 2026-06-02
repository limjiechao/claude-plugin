---
name: ink-useinput-bind
description: >-
  Diagnose and fix the Ink `useInput` bind race — the macrotask gap between
  a component's render-commit and its `useInput` handler being registered
  with Ink's stdin dispatcher. Bytes written to stdin during that gap are
  dispatched to whatever `useInput` callbacks are currently registered
  (typically just the root's Ctrl+C handler) and silently swallowed. Use
  whenever an `ink-testing-library` test silently drops its first
  `stdin.write(...)` after `render(...)`, the rendered frame proves the
  component mounted but the next keystroke does nothing, the symptom is
  intermittent on Linux but constant on Windows GHA, or the user mentions
  "ink test dropped first keystroke", "useInput race", "windows GHA flake",
  "press until" / "retry keystroke", or polling a Braille spinner glyph
  / list heading / other incidental render artefact as a wait-for-ready
  proxy. The skill is most distinctively useful for proposing the *right*
  fix — a typed `onReady` callback prop that fires from the same useEffect
  that binds `useInput` — instead of layering retries on top of fragile
  polling, and for refusing the two well-known anti-fixes (a longer
  `await tick(...)` constant, consecutive `await tick(); await tick();`).
---

# Ink `useInput` bind discipline

## Symptom

You wrote an `ink-testing-library` test like this:

```ts
const { stdin, lastFrame } = render(<HistoryList … />)
expect(lastFrame() ?? '').toContain('Past Consultations') // ← passes
stdin.write(ENTER)
await tick(60)
expect(handlerSpy).toHaveBeenCalled()                      // ← FAILS on CI
```

The first assertion proves `<HistoryList>` rendered. The second assertion
proves … nothing. On Windows GHA you see this fail 14 times in a row.
On Ubuntu it's flaky. On the dev's macOS box it always passes.

The first stdin.write was silently dropped.

## Root cause

`useInput` does **not** subscribe to stdin during render. It subscribes
inside a `useEffect`. React fires effects *after* the render commit, on
the next macrotask — meaning the sequence on first mount is:

```
render() commits  →  Ink paints  →  [next macrotask]  →  useEffect fires  →  useInput subscribes
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                              the BIND-RACE WINDOW
```

If your test writes to stdin during the bind-race window — which `ink-testing-library`'s
`stdin.write` calls are synchronous, so writes immediately after `render()` land
*inside* it — those bytes are dispatched to whichever `useInput` callbacks were
already subscribed when the write happened. Typically that's just the root host's
`Ctrl+C`-only handler, which ignores them. The child component's handler isn't bound
yet. The keystroke vanishes silently.

The window is microseconds wide on a quiet macOS dev box; it's tens of milliseconds
on a 2-CPU GHA runner. That's the entire reason these tests pass locally and fail
on CI.

## Diagnosis

If you see all of these:

- The pre-keystroke frame proves the component is mounted.
- A `tick(N)` between render and stdin.write does *not* reliably fix it.
- The same keystroke works fine in a follow-up call (e.g. retry).

You are in the bind-race window. Confirm by adding a `console.log` inside
the `useInput` callback — you'll see *some* keystrokes never reach it on
CI runs.

## Two valid fixes

### Fix 1 — Expose an `onReady` witness signal (preferred)

The fix is to make the contract explicit: the component fires a typed
callback from inside the same `useEffect` that binds `useInput`.

```tsx
interface MyComponentProps {
  // … existing props …
  /**
   * Fired exactly once per mount, after this component's useInput
   * registration has bound to Ink's stdin dispatcher. By the time
   * `onReady` is called, the next stdin.write is guaranteed to land
   * on this component's handler. Defaults to a no-op.
   */
  onReady?: () => void
}

export function MyComponent({ onReady, … }: MyComponentProps) {
  useInput((input, key) => {
    // … your handler …
  })

  // Bind-witness — registered AFTER useInput so React's commit-phase
  // effect-flush runs useInput's bind effect first.
  const onReadyFiredRef = useRef(false)
  useEffect(() => {
    if (onReadyFiredRef.current) return
    onReadyFiredRef.current = true
    onReady?.()
  }, [onReady])
  // … rest of component …
}
```

Tests then gate on the witness:

```ts
import { waitFor } from '@your/test-utils'

const onReady = vi.fn()
const { stdin } = render(<MyComponent onReady={onReady} … />)
await waitFor(() => expect(onReady).toHaveBeenCalledTimes(1))
stdin.write(ENTER)  // guaranteed to land
```

Production callers can omit `onReady`. The `useEffect` that fires it
must be **declared after** the `useInput` call so React's effect-flush
ordering puts `useInput`'s bind effect first. If you reverse them,
`onReady` fires before the binding is live and your contract is a lie.

For state-gated `useInput` (e.g. `useInput(handler, { isActive: active })`),
fire `onReady` from a `useEffect` that watches the gate — only on the
`false → true` transition, with a `wasActiveRef` to track previous
state. The contract becomes "fired once per re-arm of the input handler."

### Fix 2 — Idempotent retry (fallback)

When you can't add a callback prop (third-party component, opaque host,
fast-iterating prototype), retry the keystroke through the window:

```ts
async function pressUntil(
  stdin: { write: (data: string) => boolean },
  lastFrame: () => string | undefined,
  key: string,
  predicate: (frame: string) => boolean,
  { maxAttempts = 10, intervalMs = 20 } = {},
): Promise<void> {
  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    stdin.write(key)
    await new Promise((r) => setTimeout(r, intervalMs))
    if (predicate(lastFrame() ?? '')) return
  }
  throw new Error(`pressUntil: predicate stayed false after ${maxAttempts} retries`)
}
```

**Safety rule**: only retry keys that are **idempotent past their target
transition**. ENTER on a row that becomes `loading: true` (guarded by
`if (loading) return`) is idempotent — extra Enters are no-ops. `/` to
open a filter row that ignores its own opening key is idempotent. A
typed character is **not** — extra writes append duplicates.

`pressUntil` is fallback for situations where Fix 1 can't be applied.
Default to Fix 1.

## Anti-fixes that will not work

These are the tempting moves that look reasonable and aren't.

### Anti-fix 1 — Longer `tick(N)` constant

```ts
stdin.write(ENTER)
await tick(500)   // ← was tick(60); now `surely 500ms is enough`?
expect(…).toContain('Loaded')
```

A 500 ms wait turns a 2 % flake into a 0.5 % flake. The fundamental
problem — the wait is unbounded — is unchanged. CI under load can produce
outliers above any constant you pick. The next round of the matrix
finds the next outlier.

### Anti-fix 2 — Consecutive `await tick(); await tick();`

```ts
stdin.write(ENTER)
await tick()
await tick()
expect(…).toContain('Loaded')
```

This is the **author's confession** that one `tick()` wasn't enough.
They've met the bug. They've patched the symptom, not the cause. The
two-tick window is wider than one but still bounded. High-confidence
flake.

If you see this in code review: don't approve. Suggest Fix 1.

### Anti-fix 3 — Sentinel text in the rendered frame

```tsx
return (
  <Box>
    <Text>{`[READY]`}</Text>  {/* hidden by ANSI styling */}
    {/* rest of the component */}
  </Box>
)
```

```ts
await waitFor(() => expect(lastFrame()).toContain('[READY]'))
```

Better than nothing, but fragile. The marker survives only as long as
the render structure doesn't change. A formatting refactor silently
breaks the test. Use as a fallback when Fix 1 is impossible (third-party
component).

### Anti-fix 4 — Poll an incidental render artefact

```ts
await waitFor(() => expect(lastFrame()).toMatch(/Left Heap:\s+⠙⠹⠸⠼⠴⠦⠧⠇⠏/))
```

Polling the Braille spinner glyph advance is *the* exploit the
hexagram-generator's May 2026 `waitForSliderReady` used pre-fix. It
worked because the spinner's `setInterval` is installed by the same
`useEffect` that binds `useInput`. But that's incidental — a refactor
of the spinner or the heap readout breaks it silently. Replace with
Fix 1 the moment it's available.

## When to add `onReady` to a new component

If the component uses `useInput` and might be tested or composed with
other components whose tests cross it, **add `onReady` from the start**.
The cost is one prop + one `useEffect` (~10 lines). The cost of debugging
the bind race without it is one round of CI + half a day of "why is
Windows different."

## Case study — May 2026 hexagram-generator

Rounds 7 and 8 of the 9-round CI stabilisation surfaced this race. See
`references/case-study-rounds-7-8.md` for the commit messages, frame
sequences, and pre/post fix diffs. The salient progression:

- **Round 7** (`fa744f0`) — 3 slider-mode tests on Windows GHA dropped
  cross-cast SPACE because each cast unmounted the slider and a new
  cast mounted a fresh one; the gap between unmount and remount was the
  bind-race window. Fix landed as `waitForSliderReady` (spinner glyph
  poll — Anti-fix 4 in disguise, but it worked because of the shared
  effect ordering).
- **Round 8** (`800d3fc`) — 14 Windows + 2 Ubuntu tests in
  `history-app.test.tsx` dropped the first cross-state keystroke after
  `<HistoryList>` mount. Fix landed as `pressUntil` (Fix 2).
- **Wave 1 follow-up** (this skill's recommended path) — replaced both
  with explicit `onReady` props on `SliderInput`, `HistoryList`, and
  `CastingStatus` (Fix 1). The previous polls became redundant; the
  bind-race window stopped being something tests had to work around.

## See also

- The `cross-platform-tests` skill — covers the broader category of
  CI portability bugs this skill is one specific case of.
- `scripts/wait-for-ready.ts` — drop-in helper for the
  `await waitFor(() => expect(onReadySpy).toHaveBeenCalled())` pattern.
- `scripts/press-until.ts` — drop-in helper for the idempotent-retry
  fallback when Fix 1 isn't possible.
- `references/case-study-rounds-7-8.md` — the verbatim commit messages
  from the May 2026 stabilisation, with file/line references.
