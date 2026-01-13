import fsd from '@feature-sliced/steiger-plugin';
import { defineConfig } from 'steiger';

export default defineConfig([
  ...fsd.configs.recommended,
  {
    // disable the `public-api` rule for files in the Shared layer
    files: ['./app/frontend/**'],
    rules: {
      'fsd/ambiguous-slice-names': 'error',
      'fsd/excessive-slicing': 'warn',
      'fsd/forbidden-imports': 'error',
      'fsd/inconsistent-naming': 'error',
      'fsd/insignificant-slice': 'warn',
      'fsd/no-layer-public-api': 'error',
      'fsd/no-public-api-sidestep': 'error',
      'fsd/no-reserved-folder-names': 'error',
      'fsd/no-segmentless-slices': 'error',
      'fsd/no-segments-on-sliced-layers': 'error',
      'fsd/no-ui-in-app': 'error',
      'fsd/public-api': 'error',
      'fsd/repetitive-naming': 'warn',
      'fsd/segments-by-purpose': 'error',
      'fsd/shared-lib-grouping': 'error',
      'fsd/typo-in-layer-name': 'error',
      'fsd/no-processes': 'error',
    },
  },
]);
