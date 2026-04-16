import eslintJs from '@eslint/js';
import eslintParserTypescript from '@typescript-eslint/parser';
import eslintConfigPrettier from 'eslint-config-prettier';
import { createTypeScriptImportResolver } from 'eslint-import-resolver-typescript';
import eslintPluginImport from 'eslint-plugin-import';
import eslintPluginPrettier from 'eslint-plugin-prettier/recommended';
import eslintPluginReact from 'eslint-plugin-react';
import eslintPluginReactHooks from 'eslint-plugin-react-hooks';
import eslintPluginReactRefresh from 'eslint-plugin-react-refresh';
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
    ignores: ['dist/*', 'node_modules/*', 'app/frontend/shared/routes.ts'],
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
  eslintPluginPrettier,
  eslintConfigPrettier,
);
