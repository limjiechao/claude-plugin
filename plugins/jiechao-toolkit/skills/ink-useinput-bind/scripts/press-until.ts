/**
 * Drop-in `pressUntil` helper for the Ink `useInput` bind-race
 * mitigation — the FALLBACK when you can't add an `onReady` callback
 * prop to the component (third-party render, opaque host).
 *
 * Writes `key` to stdin and re-writes on each retry tick until
 * `predicate(frame)` returns truthy, capped at `maxAttempts` retries.
 *
 * SAFETY: only use for keys that are idempotent past their target
 * transition — ENTER on a row that becomes loading-locked, Ctrl+D on a
 * row when a confirm modal is open, `/` to open a filter that ignores
 * its own opening key. Repeating a non-idempotent key (typed character,
 * unguarded toggle) can over-fire and break the test.
 *
 * Default to `waitForReady(onReady)` (see wait-for-ready.ts) whenever
 * the component exposes an onReady prop.
 *
 * Usage:
 *
 *   const { stdin, lastFrame } = render(<HistoryList … />)
 *   await pressUntil(stdin, lastFrame, ENTER, (frame) =>
 *     frame.includes('Consultation · loaded'),
 *   )
 *
 * See SKILL.md for the full pattern.
 */

interface StdinLike {
  write: (data: string) => boolean
}

interface PressUntilOptions {
  /** Max retries before giving up. Default 10. */
  maxAttempts?: number
  /** Delay between retries. Default 20 ms. */
  intervalMs?: number
}

export async function pressUntil(
  stdin: StdinLike,
  lastFrame: () => string | undefined,
  key: string,
  predicate: (frame: string) => boolean,
  { maxAttempts = 10, intervalMs = 20 }: PressUntilOptions = {},
): Promise<void> {
  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    stdin.write(key)
    await new Promise((resolve) => setTimeout(resolve, intervalMs))
    if (predicate(lastFrame() ?? '')) return
  }
  throw new Error(
    `pressUntil: predicate stayed false after ${maxAttempts} retries`,
  )
}
