# Self-hosted web fonts, v1

Every Flow page, the static error pages in `public/` and the admin panel load
`/fonts/v1/fonts.css`, so no browser asks Google for a font (task #353).

| Family | Source package | Axis | Subsets |
|---|---|---|---|
| Inter | `@fontsource-variable/inter` 5.3.0 | `wght` 100–900 | latin, latin-ext, cyrillic, cyrillic-ext, greek, greek-ext, vietnamese |
| JetBrains Mono | `@fontsource-variable/jetbrains-mono` 5.3.0 | `wght` 100–800 | latin, latin-ext, cyrillic, cyrillic-ext, greek, vietnamese |
| Spline Sans Mono | `@fontsource-variable/spline-sans-mono` 5.3.0 | `wght` 300–700 | latin, latin-ext |

The `woff2` files are the packages' `files/*-wght-normal.woff2`, unchanged; `fonts.css`
is their `index.css` with the family names Google uses (`Inter`, not `Inter Variable`),
which `app/frontend/shared/theme/mantineTheme.ts` names. All three are under the SIL Open
Font License 1.1 (`OFL-*.txt`).

Production serves `public/` with a one-year `cache-control` and no digest, so a file
here never changes in place: a font update goes into `public/fonts/v2/`, and the
references to `/fonts/v1/` move with it.
