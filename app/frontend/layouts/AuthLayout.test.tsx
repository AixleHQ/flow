import '@testing-library/jest-dom/vitest';
import { notifications } from '@mantine/notifications';
import { beforeEach, describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, waitFor } from 'test/renderPage';

import { AuthLayout } from './AuthLayout';

describe('AuthLayout flash notifications', () => {
  // Notifications live in a global Mantine store; a persistent (autoClose:false)
  // notice from one test would otherwise leak into the next.
  beforeEach(() => notifications.clean());

  it('shows a persistent "needs setup" notification from flash.needsSetup (camelCased key)', async () => {
    const needsSetupLine =
      'Secrets, assets, repositories and integrations are not copied — add/connect them in the project as needed.';

    renderAuthedPage(<AuthLayout>{<div>content</div>}</AuthLayout>, {
      props: { flash: { notice: 'Copied', needsSetup: [needsSetupLine] } },
    });

    // Regression: Inertia camelizes prop keys, so the Rails `needs_setup` flash arrives as
    // `needsSetup`. Reading the snake_case key silently missed it and the notice never rendered.
    await waitFor(() => {
      expect(screen.getByText('Some resources need setup')).toBeInTheDocument();
    });
    expect(screen.getByText(needsSetupLine)).toBeInTheDocument();
  });

  it('does not fire a needs-setup notice when flash has no needsSetup', async () => {
    renderAuthedPage(<AuthLayout>{<div>content</div>}</AuthLayout>, { props: { flash: {} } });

    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(screen.queryByText('Some resources need setup')).not.toBeInTheDocument();
  });
});
