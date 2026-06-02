/**
 * Polling `waitFor` — the cross-platform replacement for `await tick(60)`.
 *
 * Wrap any assertion or condition that depends on async work completing.
 * `waitFor` retries the predicate until it returns without throwing, or the
 * timeout elapses. The last error is rethrown on timeout so failures keep
 * their original stack trace and message.
 *
 * Two shapes:
 *
 *   // (a) Wrap an expect — the assertion *is* the condition
 *   await waitFor(() => {
 *     expect(stripAnsi(lastFrame() ?? '')).toContain('Loaded')
 *   })
 *
 *   // (b) Return the matched value
 *   const row = await waitFor(() => {
 *     const found = rows().find((r) => r.id === expectedId)
 *     if (!found) throw new Error('row not yet visible')
 *     return found
 *   })
 *
 * Defaults: 2000ms timeout, 10ms poll. The timeout is generous because the
 * cost of a high ceiling is only paid on a real failure — a passing test
 * only takes the actual time the work needs.
 */
export async function waitFor<T>(
  predicate: () => T | Promise<T>,
  { timeoutMs = 2000, intervalMs = 10 }: { timeoutMs?: number; intervalMs?: number } = {},
): Promise<T> {
  const deadline = Date.now() + timeoutMs
  let lastError: unknown
  for (;;) {
    try {
      return await predicate()
    } catch (error) {
      lastError = error
    }
    if (Date.now() >= deadline) {
      throw lastError ?? new Error(`waitFor timed out after ${timeoutMs}ms`)
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs))
  }
}
