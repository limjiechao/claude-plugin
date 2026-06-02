---
name: ssr-client-divergence
description: |
  Use `useSyncExternalStore` with server/client snapshots when a React
  component must render differently on the server vs after hydration.
  Do NOT use `useState` + `useEffect(() => setMounted(true))` — it
  triggers `react-hooks/set-state-in-effect` and causes a cascading
  double render. Triggers on: hydration mismatch, "Hydration failed",
  "Text content does not match", SSR/CSR split, useSyncExternalStore,
  isMounted state, ClientOnly wrapper, browser-only API (window,
  document), portals, createPortal, `typeof window` guards. Use when
  writing a component that touches browser globals, or when debugging
  hydration errors.
---

# SSR / client divergence: `useSyncExternalStore`, not `setState` in `useEffect`

> Supersedes the `useState` + `useEffect` recipe for "mounted" state. The
> older pattern triggers `react-hooks/set-state-in-effect` and causes a
> cascading double render. This is the React-recommended way to express
> "render differently on server vs after hydration."

When a component must render differently on the server (SSR) versus the
client — portals, `window`/`document` access, or any browser-only API —
use `useSyncExternalStore` with separate server and client snapshots.

## Why not `useState` + `useEffect`

```tsx
// ❌ Triggers react-hooks/set-state-in-effect lint error;
// causes a cascading double render.
const [mounted, setMounted] = useState(false);
useEffect(() => {
  setMounted(true); // setState called synchronously inside an effect
}, []);
```

## Canonical pattern

```tsx
'use client';

import { useSyncExternalStore, type ReactNode } from 'react';

function subscribe() {
  return () => {};
}

function MyClientOnlyComponent({ children }: { children: ReactNode }) {
  const isMounted = useSyncExternalStore(
    subscribe,    // no-op: no external store to subscribe to
    () => true,   // client snapshot: mounted, safe to use browser APIs
    () => false,  // server snapshot: not mounted, skip client-only code
  );

  if (!isMounted) return null;

  // browser-only code here (document, window, createPortal, etc.)
  return <>{children}</>;
}
```

## Rules

- Always add `'use client'` — components that use browser globals are
  never server components.
- The `subscribe` no-op (`() => () => {}`) is correct: there is no
  external store, only the server/client snapshot split.
- Return `null` (or a server-safe fallback) when `!isMounted`. This is
  the correct SSR behavior for portals and browser-only UIs.
- Do **not** add `typeof window !== 'undefined'` guards as an
  alternative — they cause hydration mismatches when the server and
  client produce different HTML.
- Do **not** wrap browser APIs in `useState` + `useEffect` "mounted"
  flags. The lint error (`react-hooks/set-state-in-effect`) is correct;
  the cascading render is real.
