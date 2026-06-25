import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { act, renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { RegistrySearchModal } from './SkillsContent';

// Demonstrates asserting that a UI interaction fires the expected BACKEND request.
// The registry search debounces and calls router.reload({ data: { q }, only: [...] }).
// router is mocked (a vi.fn spy) in test/setup.ts, so we assert it was called — without a backend.
describe('RegistrySearchModal — server-side search fires a backend request', () => {
  it('typing a query triggers router.reload with that query', async () => {
    renderPage(
      <RegistrySearchModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/skills"
        installedPackages={new Set<string>()}
        initialQuery=""
        results={[]}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText(/search skills/i), 'react');

    await waitFor(() =>
      expect(router.reload).toHaveBeenCalledWith(
        expect.objectContaining({ data: { q: 'react' }, only: ['registryQuery', 'registryResults'] }),
      ),
    );
  });

  it('does NOT hit the backend for a single character (min 2 chars)', async () => {
    renderPage(
      <RegistrySearchModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/skills"
        installedPackages={new Set<string>()}
        initialQuery=""
        results={[]}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText(/search skills/i), 'r');
    // let the 400ms debounce elapse; wrap in act so Mantine's modal state settles cleanly
    await act(async () => {
      await new Promise((resolve) => setTimeout(resolve, 500));
    });

    expect(router.reload).not.toHaveBeenCalled();
  });
});
