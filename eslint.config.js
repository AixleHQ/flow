import eslintJs from '@eslint/js';
import eslintParserTypescript from '@typescript-eslint/parser';
import eslintConfigPrettier from 'eslint-config-prettier';
import { createTypeScriptImportResolver } from 'eslint-import-resolver-typescript';
import eslintPluginImport from 'eslint-plugin-import';
import eslintPluginPrettier from 'eslint-plugin-prettier/recommended';
import eslintPluginReact from 'eslint-plugin-react';
import eslintPluginReactHooks from 'eslint-plugin-react-hooks';
import eslintPluginReactRefresh from 'eslint-plugin-react-refresh';
import eslintPluginTestingLibrary from 'eslint-plugin-testing-library';
import globals from 'globals';
import typescriptEslint from 'typescript-eslint';

export default typescriptEslint.config(
  eslintJs.configs.recommended,
  typescriptEslint.configs.recommended,
  eslintPluginImport.flatConfigs.recommended,
  {
    files: ['**/*.{js,jsx,ts,tsx}'],
  },
  {
    // Auto-generated, DO-NOT-EDIT outputs (Typelizer types + route helpers).
    // Their formatting is the generator's, not Prettier's — don't lint them.
    ignores: ['dist/*', 'node_modules/*', 'app/frontend/shared/routes.ts', 'app/frontend/types/generated/**'],
  },
  {
    languageOptions: {
      parser: eslintParserTypescript,
      parserOptions: {
        ecmaFeatures: {
          jsx: true,
        },
        ecmaVersion: 'latest',
        sourceType: 'module',
      },
      globals: {
        ...globals.browser,
        RequestInit: true,
        Settings: true,
      },
    },
  },
  {
    plugins: {
      react: eslintPluginReact,
      'react-refresh': eslintPluginReactRefresh,
      'react-hooks': eslintPluginReactHooks,
    },
  },
  {
    rules: {
      ...eslintPluginReact.configs.recommended.rules,
      'react-refresh/only-export-components': ['warn', { allowConstantExport: true }],
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'warn',
      'react/react-in-jsx-scope': 'off', // No need because of React 17+
      'react/prop-types': 'off', // No need because of TypeScript
      'import/order': [
        'error',
        {
          groups: ['builtin', 'external', 'internal', 'parent', 'sibling', 'index'],
          'newlines-between': 'always',
          pathGroups: [
            {
              pattern: '+(pages|entities|features|shared|widgets)/**',
              group: 'internal',
              position: 'after',
            },
          ],
          alphabetize: {
            order: 'asc',
            caseInsensitive: true,
          },
          pathGroupsExcludedImportTypes: [],
        },
      ],
    },
  },
  {
    settings: {
      react: {
        version: 'detect',
      },
      'import/resolver': {
        typescript: createTypeScriptImportResolver(),
      },
    },
  },
  // The --app-* token contract. Raw hex outside mantineTheme.ts is how the app
  // ended up with four competing color systems (Aixle tokens, Material 500,
  // GitHub greens, a stray Tailwind set) and a light theme that did not match
  // its dark one. Vendor brand marks are the one legitimate exception; keep
  // them in a named constant with an eslint-disable-next-line and a reason.
  {
    files: ['app/frontend/**/*.{ts,tsx}'],
    ignores: ['app/frontend/shared/theme/**', 'app/frontend/**/*.{test,spec}.{ts,tsx}'],
    rules: {
      'no-restricted-syntax': [
        'error',
        {
          selector: "Literal[value=/^#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/]",
          message:
            'Hardcoded color. Use an --app-* token from shared/theme/mantineTheme.ts (or CHART_SERIES from shared/theme/chartPalette.ts for series colors).',
        },
        {
          selector: "TemplateElement[value.raw=/#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\\b/]",
          message:
            'Hardcoded color in a template literal. Use an --app-* token from shared/theme/mantineTheme.ts.',
        },
      ],
    },
  },
  // Testing doctrine for component/page tests (docs/testing.md, rule R8):
  // query by role/label through Testing Library, never reach into the DOM or
  // snapshot Mantine's hashed markup.
  {
    ...eslintPluginTestingLibrary.configs['flat/react'],
    files: ['app/frontend/**/*.{test,spec}.{ts,tsx}'],
  },
  {
    files: ['app/frontend/**/*.{test,spec}.{ts,tsx}'],
    rules: {
      'no-restricted-properties': [
        'error',
        {
          property: 'toMatchSnapshot',
          message:
            'Snapshot tests flap on every Mantine bump (hashed .m-* classes). Assert roles/text/behavior instead (docs/testing.md R8).',
        },
        {
          property: 'toMatchInlineSnapshot',
          message:
            'Snapshot tests flap on every Mantine bump (hashed .m-* classes). Assert roles/text/behavior instead (docs/testing.md R8).',
        },
      ],
    },
  },
  {
    // Pre-doctrine offenders, frozen 2026-07-02 (64 querySelector sites) —
    // this list only ever shrinks. New tests must satisfy the full rule set.
    files: [
      'app/frontend/pages/Auth/GoogleLoginButton.test.tsx',
      'app/frontend/pages/Docs/components/DocsCallout.test.tsx',
      'app/frontend/pages/Projects/Board/BoardPage.test.tsx',
      'app/frontend/pages/Projects/Sessions/SessionsPage.test.tsx',
      'app/frontend/pages/Projects/WorkflowRuns/ShowPage.test.tsx',
      'app/frontend/pages/Projects/Workflows/BuilderPage.test.tsx',
      'app/frontend/pages/Projects/Workflows/WorkflowsPage.test.tsx',
      'app/frontend/shared/components/SessionShowContent/SessionShowContent.test.tsx',
      'app/frontend/shared/resources/agents/AgentsContent.test.tsx',
      'app/frontend/shared/resources/assets/AssetPreviewModal.test.tsx',
      'app/frontend/shared/resources/assets/AssetsContent.test.tsx',
      'app/frontend/shared/resources/config-items/ConfigItemsContent.test.tsx',
      'app/frontend/shared/resources/mcp-servers/McpServerFormModal.test.tsx',
      'app/frontend/shared/resources/mcp-servers/McpServersContent.test.tsx',
      'app/frontend/shared/resources/tools/ToolFileEditor.test.tsx',
      'app/frontend/shared/resources/tools/ToolsContent.test.tsx',
    ],
    rules: {
      'testing-library/no-node-access': 'off',
      'testing-library/no-container': 'off',
    },
  },
  eslintPluginPrettier,
  eslintConfigPrettier,
);
