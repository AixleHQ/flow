import fsd from '@feature-sliced/steiger-plugin';
import { defineConfig } from 'steiger';

export default defineConfig([
  ...fsd.configs.recommended,
  {
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
  // Architectural exceptions:
  // - shared/api needs terminal-session types for API contracts
  // - shared/lib/hooks needs terminal-session types for websocket handling
  // - features/agent-auth uses widgets/terminal-session for terminal UI
  // These are intentional cross-layer imports due to terminal session being a core infrastructure concept
  {
    files: [
      './app/frontend/shared/api/terminalSessionApi.ts',
      './app/frontend/shared/lib/hooks/useTerminalSessionChannel.ts',
    ],
    rules: {
      'fsd/forbidden-imports': 'off',
    },
  },
  {
    files: ['./app/frontend/features/agent-auth/**'],
    rules: {
      'fsd/forbidden-imports': 'off',
    },
  },
]);
