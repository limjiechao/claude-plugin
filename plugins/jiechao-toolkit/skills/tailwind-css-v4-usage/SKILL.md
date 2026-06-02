---
name: tailwind-css-v4-usage
description: |
  Tailwind CSS 4 is CSS-first — no `tailwind.config.js`. All configuration
  lives in CSS via `@theme`, `@source`, `@plugin`, `@utility`, and
  `@custom-variant`. Triggers on: Tailwind v4, Tailwind CSS 4,
  @tailwindcss/postcss, @theme, @source, @plugin, @utility,
  @custom-variant, @layer, CSS-first config, missing utility classes in
  production, "tailwind.config not picked up". Use when adding or
  changing Tailwind setup, theme tokens, content scanning paths, plugins,
  or PostCSS config; or when classes from a newly added package are not
  generated.
---

# Tailwind CSS v4 Usage

Tailwind v4 is **CSS-first**: no `tailwind.config.js` / `tailwind.config.ts`.
All configuration lives in CSS via `@theme`, `@source`, `@plugin`,
`@utility`, and `@custom-variant`.

## Goals

- **Keep configuration in CSS** — Tailwind v4 directives are the single
  source of truth. No JS config for theme/content/plugins.
- **Use one shared theme entry** when a design system exists, so tokens
  and utilities stay consistent across apps.
- **Keep `@source` complete** — every file that contains Tailwind classes
  must be scanned, including consumed monorepo packages.
- **Use PostCSS only with `@tailwindcss/postcss`** for the Tailwind
  pipeline.

## Key rules

### No `tailwind.config.js` / `tailwind.config.ts`

Do not add or rely on a JavaScript/TypeScript Tailwind config file.
Tailwind v4 uses CSS-based configuration. Put theme, content, plugins,
and custom utilities in CSS via `@theme`, `@source`, `@plugin`,
`@utility`, `@custom-variant`.

### PostCSS

Use **only** `@tailwindcss/postcss` in `postcss.config.mjs` (or
equivalent). Do not add the legacy `tailwindcss` PostCSS plugin or
duplicate Tailwind entry points.

```js
/** @type {import('postcss-load-config').Config} */
const config = {
  plugins: {
    '@tailwindcss/postcss': {},
  },
};
export default config;
```

### CSS entry and layering

- **Apps consuming a shared theme package:**
  - Import the shared theme first, then add app-specific directives:
    ```css
    @import 'your-shared-theme/globals.css';  /* brings in Tailwind + tokens */
    @plugin '@tailwindcss/typography';        /* if using prose */
    /* app-specific @theme, @utility, @custom-variant, @source ... */
    ```
- **Apps without a shared theme:**
  - `@import 'tailwindcss';` directly, then declare `@theme`, `@source`,
    plugins.
- **Theme/design-system package:**
  - Owns `@import 'tailwindcss';`, the `@theme inline { … }` block
    (breakpoints, radii, colors, animations), `@custom-variant dark`,
    `@utility container`, `@layer utilities`, and any plugin
    registration. Apps consume it via a single import.

Keep main entry CSS files focused on imports + Tailwind directives.
Avoid stuffing one-off selectors there unless they are part of theme
or utility definitions.

### `@source` (content scanning)

Tailwind v4 discovers class names from files listed in `@source`. **Every
file that contains Tailwind utility classes must be covered** by an
`@source` glob, or those classes will not be generated.

- **Apps:** list (1) the app's own source paths using the package's
  internal subpath aliases (e.g. `#app/**/*.{js,ts,jsx,tsx,mdx}`,
  `#components/**/*.{js,ts,jsx,tsx,mdx}`, `#utils/**/*.{js,ts,jsx,tsx,mdx}`),
  and (2) paths to **every consumed monorepo package** that contains
  Tailwind classes. Use paths relative to the app into `node_modules`
  (e.g.
  `../../../../node_modules/pkg-name/src/components/**/*.{js,ts,jsx,tsx,mdx}`).
  When you add a new dependency that uses Tailwind classes, add a
  corresponding `@source` line.
- **Theme package:** `@source` points at theme dist and any local files
  that need to be scanned. Do not add app or other feature paths here.
- Do **not** use TypeScript path aliases in `@source`; use the same
  subpath aliases as in `package.json` `imports` (e.g. `#app/*`,
  `#components/*`) for the current package, and relative paths for
  `node_modules`.

### `@theme` and `@theme inline`

- **Design tokens** (breakpoints, colors, radii, animations) belong in
  the shared theme package inside `@theme inline { … }`. Use CSS
  variables (e.g. `--breakpoint-2xl`, `--radius-lg`, `--animate-*`).
- **Apps** may extend with a plain `@theme { }` block for app-only
  overrides (e.g. `--breakpoint-2xl: 1800px;`). Do not redefine the full
  design system in app CSS; extend theme variables.

### `@utility`

Use `@utility` for custom utility classes (e.g. `container` with
responsive behavior). Define variants with `@variant` (e.g. breakpoints).
Prefer reusing or extending the theme's `container` rather than
redefining from scratch.

### `@custom-variant`

Use for custom variants (e.g. `dark` via `&:is(.dark *)`, or
`not-last`). Define in the theme when global; in app globals when
app-specific.

### `@plugin`

Use `@plugin '@tailwindcss/typography';` in app globals when the app
uses prose/content styling. Theme packages may register local plugins
(e.g. `@plugin '#src/plugin.ts';`). Don't add plugins that duplicate or
conflict with the theme.

### `@layer` and `@apply`

Use `@layer utilities` (or other layers) for small global overrides
(e.g. `scrollbar-hide`, body defaults) in the theme package. Use
`@apply` sparingly and only for cohesive base styles; prefer utility
classes in components.

### Dependencies

Any package that compiles CSS with Tailwind must list `tailwindcss`
(and `@tailwindcss/postcss` if it has its own PostCSS build) in
`devDependencies` / `dependencies` as appropriate. Packages that are
only **scanned** via an app's `@source` do not need their own Tailwind
build.

## Do / Don't examples

**App `globals.css`**
- ✅ Import the shared theme (or `tailwindcss` directly), then
  `@plugin`, `@theme`, `@utility`, `@custom-variant`, and a full
  `@source` list (app aliases + all monorepo packages that use Tailwind).
- ❌ Add a `tailwind.config.ts` or `tailwind.config.js`.
- ❌ `@import 'tailwindcss';` again in the app if you already import a
  shared theme that includes it.

**Adding a new feature package consumed by an app**
- ✅ Add an `@source` line in the app's `globals.css` pointing at that
  package's source in `node_modules` (e.g. `@source
  '../../../../node_modules/pkg-name/src/**/*.{js,ts,jsx,tsx,mdx}';`).
- ❌ Forget to add `@source` for the new package — missing content =
  missing classes in production.

**Theme tokens**
- ✅ Add new design tokens (breakpoints, colors, radii, animations) in
  the shared theme package's `theme.css` inside `@theme inline { }`.
- ❌ Define a full set of theme variables in each app; reuse and extend
  from the theme.

**PostCSS**
- ✅ `plugins: { '@tailwindcss/postcss': {} }` only.
- ❌ Add the old `tailwindcss` or `autoprefixer` plugins for Tailwind;
  v4 PostCSS handles it.

## Related

- [[package-public-api]] — use the same `#…` subpath aliases in
  `@source` as in `package.json` `imports`; never TypeScript path
  aliases.
- [[no-barrel-files]] — CSS entry files are single-purpose (imports +
  directives); don't use barrel-style re-exports for Tailwind config.

## External docs

- Tailwind v4: [tailwindcss.com](https://tailwindcss.com) — CSS-first
  configuration, `@theme`, `@source`, `@plugin`, `@utility`,
  `@custom-variant`.
