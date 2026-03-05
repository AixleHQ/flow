import fsd from '@feature-sliced/steiger-plugin';
import { defineConfig } from 'steiger';

export default defineConfig([
  ...fsd.configs.recommended,
  {
    rules: {
      'fsd/forbidden-imports': 'warn',
      'fsd/insignificant-slice': 'warn',
      'fsd/no-public-api-sidestep': 'warn',
    },
  },
]);
