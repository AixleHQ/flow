import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { notifications } from '@mantine/notifications';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { act, renderPage, screen } from 'test/renderPage';

import { registerInertiaNetworkErrorNotice } from './inertiaNetworkErrorNotice';

const networkError = () => {
  const call = vi
    .mocked(router.on)
    .mock.calls.filter(([name]) => name === 'networkError')
    .at(-1);
  const listener = call?.[1] as unknown as (event: CustomEvent) => void;
  const event = new CustomEvent('inertia:networkError', {
    cancelable: true,
    detail: { error: new Error('Network error') },
  });
  act(() => listener(event));
  return event;
};

describe('registerInertiaNetworkErrorNotice', () => {
  let unregister: () => void;

  beforeEach(() => {
    notifications.clean();
  });

  afterEach(() => {
    unregister?.();
  });

  it('says the server cannot be reached, once, instead of failing the visit', async () => {
    unregister = registerInertiaNetworkErrorNotice();
    renderPage(<div />);

    const first = networkError();
    networkError();

    expect(first.defaultPrevented).toBe(true);
    expect(await screen.findByText("Can't reach the server")).toBeInTheDocument();
    expect(screen.getAllByText("Can't reach the server")).toHaveLength(1);
  });
});
