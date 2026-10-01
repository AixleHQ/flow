import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { buildSharedUser } from 'test/factories/sharedProps';
import { inertiaState } from 'test/inertiaMock';
import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import { NewSessionDrawer } from './NewSessionDrawer';
import type { CreateOptions } from './useCreateOptions';

const createOptions: CreateOptions = {
  agents: [],
  tools: [],
  toolGroups: [],
  skills: [],
  mcpServers: [],
  assets: [],
  repositories: [{ id: 1, name: 'acme/app' }],
  agentModels: [],
  configuredAgents: ['claude_code'],
  defaultAgentRuntime: 'claude_code',
  workflows: [],
  configItems: [],
};

const pageProps = {
  createOptions,
  currentUser: buildSharedUser({ configuredAgents: ['claude_code'], defaultAgentRuntime: 'claude_code' }),
};

const discardDialog = () => screen.findByRole('dialog', { name: 'Discard unsaved changes?' });

describe('NewSessionDrawer', () => {
  it('asks before closing over a typed prompt, and closes once the user discards it', async () => {
    const onClose = vi.fn();
    renderAuthedPage(<NewSessionDrawer projectId={7} opened onClose={onClose} />, { props: pageProps });

    await userEvent.click(screen.getByRole('radio', { name: /Automatic/ }));
    await userEvent.type(screen.getByRole('textbox', { name: /initial prompt/i }), 'Refactor the auth module');
    await userEvent.click(screen.getByRole('button', { name: 'Close' }));

    const discard = await discardDialog();
    expect(onClose).not.toHaveBeenCalled();
    expect(screen.getByRole('textbox', { name: /initial prompt/i })).toHaveValue('Refactor the auth module');

    await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('closes an untouched drawer without asking, with the default runtime preselected', async () => {
    const onClose = vi.fn();
    renderAuthedPage(<NewSessionDrawer projectId={7} opened onClose={onClose} />, { props: pageProps });

    expect(screen.getByRole('button', { name: /Claude Code/ })).toHaveAttribute('aria-pressed', 'true');
    await userEvent.click(screen.getByRole('button', { name: 'Close' }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });

  it('starts clean again when reopened after a discarded draft', async () => {
    const onClose = vi.fn();
    const { rerender } = renderAuthedPage(<NewSessionDrawer projectId={7} opened onClose={onClose} />, {
      props: pageProps,
    });

    await userEvent.click(screen.getByRole('switch', { name: /Use BMAD Method/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Close' }));
    await userEvent.click(within(await discardDialog()).getByRole('button', { name: 'Discard' }));
    rerender(<NewSessionDrawer projectId={7} opened={false} onClose={onClose} />);
    rerender(<NewSessionDrawer projectId={7} opened onClose={onClose} />);

    expect(screen.getByRole('switch', { name: /Use BMAD Method/ })).not.toBeChecked();
    await userEvent.click(screen.getByRole('button', { name: 'Close' }));

    expect(onClose).toHaveBeenCalledTimes(2);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });

  it('does not ask on a reopen still loading its options, after a discarded draft', async () => {
    const onClose = vi.fn();
    const { rerender } = renderAuthedPage(<NewSessionDrawer projectId={7} opened onClose={onClose} />, {
      props: pageProps,
    });

    await userEvent.click(screen.getByRole('switch', { name: /Use BMAD Method/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Close' }));
    await userEvent.click(within(await discardDialog()).getByRole('button', { name: 'Discard' }));
    rerender(<NewSessionDrawer projectId={7} opened={false} onClose={onClose} />);
    inertiaState.pageProps = { ...inertiaState.pageProps, createOptions: undefined };
    rerender(<NewSessionDrawer projectId={7} opened onClose={onClose} />);

    await userEvent.click(screen.getByRole('button', { name: 'Close' }));

    expect(onClose).toHaveBeenCalledTimes(2);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });
});
