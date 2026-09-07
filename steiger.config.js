import fsd from '@feature-sliced/steiger-plugin';
import { defineConfig } from 'steiger';

// Feature-Sliced Design check for the frontend (app/frontend).
//
// This codebase uses a deliberately loose FSD interpretation (see
// docs/project/context.md "Frontend: Component Structure"): only the `pages`
// and `shared` layers, per-component `index.ts` barrels rather than
// per-segment ones, and pages kept flat instead of split into ui/model/api
// segments. The rules below are turned off where the vanilla FSD default
// fights that documented convention; the structural rules that guard the
// layer boundaries (import direction, cross-slice access, reserved names)
// stay on.
export default defineConfig([
  ...fsd.configs.recommended,
  {
    ignores: [
      './app/frontend/types/**',
      './app/frontend/test/**',
      './app/frontend/**/*.test.{ts,tsx}',
      './app/frontend/vite-env.d.ts',
    ],
  },
  {
    rules: {
      // Pages are intentionally flat — components co-located, no ui/model/api split.
      'fsd/no-segmentless-slices': 'off',
      // The project's barrel convention is per-component folders, not per-segment.
      'fsd/public-api': 'off',
      // `shared/components` and `shared/analytics` are the documented segment names.
      'fsd/segments-by-purpose': 'off',
      // Advisory grouping hints — not worth churning the tree over.
      'fsd/shared-lib-grouping': 'off',
      'fsd/insignificant-slice': 'off',
    },
  },
]);
