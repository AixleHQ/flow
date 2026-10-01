import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { buildProjectTracker } from 'test/factories/projectTracker';
import { renderPage, screen, userEvent, within } from 'test/renderPage';

import { EditHandleDrawer } from './EditHandleDrawer';

const basePath = '/company/projects/7/trackers';

describe('EditHandleDrawer', () => {
  it('opens on the current handle and closes without asking while it is unchanged', async () => {
    const onClose = vi.fn();
    renderPage(<EditHandleDrawer tracker={buildProjectTracker()} basePath={basePath} onClose={onClose} />);

    expect(screen.getByRole('textbox', { name: 'Handle' })).toHaveValue('customer-platform');
    await userEvent.click(screen.getByRole('button', { name: 'Close' }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });

  it('asks before closing over an edited handle, and closes once the user discards', async () => {
    const onClose = vi.fn();
    renderPage(<EditHandleDrawer tracker={buildProjectTracker()} basePath={basePath} onClose={onClose} />);

    await userEvent.type(screen.getByRole('textbox', { name: 'Handle' }), '-v2');
    await userEvent.click(screen.getByRole('button', { name: 'Close' }));

    const discard = await screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
    expect(onClose).not.toHaveBeenCalled();
    await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });
});
