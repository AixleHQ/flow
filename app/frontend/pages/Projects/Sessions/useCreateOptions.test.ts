import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { inertiaState } from 'test/inertiaMock';
import { renderHook, waitFor } from 'test/renderPage';

import { useCreateOptions } from './useCreateOptions';

describe('useCreateOptions', () => {
  afterEach(() => {
    vi.clearAllMocks();
    inertiaState.pageProps = {};
  });

  it('calls router.reload with the snake_case prop key when opened without createOptions', async () => {
    inertiaState.pageProps = {};

    renderHook(() => useCreateOptions(true));

    await waitFor(() => expect(router.reload).toHaveBeenCalledWith({ only: ['create_options'] }));
  });

  it('does not call router.reload when opened is false', async () => {
    inertiaState.pageProps = {};

    renderHook(() => useCreateOptions(false));

    await waitFor(() => expect(router.reload).not.toHaveBeenCalled());
  });

  it('does not call router.reload when createOptions is already present', async () => {
    inertiaState.pageProps = {
      createOptions: {
        agents: [],
        tools: [],
        skills: [],
        mcpServers: [],
        assets: [],
        repositories: [],
        agentModels: [],
        configuredAgents: [],
        defaultAgentRuntime: null,
        workflows: [],
        configItems: [],
      },
    };

    renderHook(() => useCreateOptions(true));

    await waitFor(() => expect(router.reload).not.toHaveBeenCalled());
  });
});
