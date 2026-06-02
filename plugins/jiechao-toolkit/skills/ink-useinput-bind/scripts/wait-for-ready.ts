/**
 * Drop-in `waitForReady` helper for the Ink `useInput` bind-race
 * mitigation. Wait for a component's `onReady?: () => void` callback
 * spy to have been invoked at least once. By the time the spy fires,
 * the component's `useInput` handler is bound to Ink's stdin dispatcher
 * and the next `stdin.write(...)` will land on it.
 *
 * Usage:
 *
 *   import { render } from 'ink-testing-library'
 *   import { vi } from 'vitest'
 *
 *   const onReady = vi.fn()
 *   const { stdin } = render(<MyComponent onReady={onReady} />)
 *   await waitForReady(onReady)
 *   stdin.write(ENTER)  // guaranteed to be received
 *
 * See SKILL.md for the full pattern.
 */

interface MockLike {
  mock: { calls: ReadonlyArray<unknown> }
}

interface WaitForReadyOptions {
  /** Default 4 s. Adjust per package to match its observed worst case. */
  timeoutMs?: number
  /** Polling interval. Default 20 ms. */
  intervalMs?: number
}

export async function waitForReady(
  spy: MockLike,
  { timeoutMs = 4000, intervalMs = 20 }: WaitForReadyOptions = {},
): Promise<void> {
  const deadline = Date.now() + timeoutMs
  for (;;) {
    if (spy.mock.calls.length > 0) return
    if (Date.now() >= deadline) {
      throw new Error(
        `waitForReady: onReady was not called within ${timeoutMs}ms`,
      )
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs))
  }
}
