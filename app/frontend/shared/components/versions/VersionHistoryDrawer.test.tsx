import { describe, expect, it, vi } from 'vitest';

import type { EntityVersion, EntityVersionDetail } from '@/types/generated';
import { answerFetch, jsonResponse } from 'test/fetchStub';
import { renderPage, screen, userEvent, within } from 'test/renderPage';

import { revertWarnings } from 'shared/lib/versionHistory';

import { VersionHistoryDrawer } from './VersionHistoryDrawer';

const version = (overrides: Partial<EntityVersion>): EntityVersion => ({
  id: 1,
  number: 1,
  versionableType: 'Agent',
  versionableId: 5,
  terminalSessionId: null,
  createdAt: '2026-09-25T10:00:00Z',
  event: 'saved',
  source: 'ui',
  author: { id: 1, name: 'Ada' },
  restoredFromNumber: null,
  baseline: false,
  duplicatedFromId: null,
  disabledTriggerIds: [],
  ...overrides,
});

const detail = (overrides: Partial<EntityVersionDetail>): EntityVersionDetail => ({
  ...version({ id: 11, number: 1 }),
  snapshot: { title: 'Coder', persona: 'writes code' },
  previousSnapshot: null,
  currentSnapshot: { title: 'Senior Coder', persona: 'writes code' },
  currentVersionNumber: 2,
  references: {},
  ...overrides,
});

const listPath = '/api/v1/projects/7/entity_versions';

function renderDrawer(props: Partial<Parameters<typeof VersionHistoryDrawer>[0]> = {}) {
  return renderPage(
    <VersionHistoryDrawer
      opened
      onClose={vi.fn()}
      projectId={7}
      versionableType="Agent"
      versionableId={5}
      title="Coder"
      canRevert
      {...props}
    />,
  );
}

describe('VersionHistoryDrawer', () => {
  it('lists versions newest first, naming who made each and how', async () => {
    answerFetch({
      [`GET ${listPath}`]: {
        versions: [
          version({ id: 12, number: 2, source: 'builder', author: { id: 1, name: 'Ada' } }),
          version({ id: 11, number: 1, event: 'created', baseline: true, source: 'system', author: null }),
        ],
        nextBefore: null,
        currentVersionNumber: 2,
      },
    });

    renderDrawer();

    expect(await screen.findByText('Initial state')).toBeInTheDocument();
    expect(screen.getByText('Ada by Aixle Builder')).toBeInTheDocument();
    expect(screen.getByText('current')).toBeInTheDocument();
  });

  it('shows what a version changed, and switches to comparing it with the current one', async () => {
    answerFetch({
      [`GET ${listPath}`]: {
        versions: [version({ id: 12, number: 2 }), version({ id: 11, number: 1 })],
        nextBefore: null,
        currentVersionNumber: 2,
      },
      [`GET ${listPath}/11`]: detail({ previousSnapshot: { title: 'Draft', persona: 'writes code' } }),
    });

    renderDrawer();
    await userEvent.click(await screen.findByRole('button', { name: /v1 Saved/ }));

    expect(await screen.findByText('Draft')).toBeInTheDocument();
    expect(screen.getByText('Coder')).toBeInTheDocument();

    await userEvent.click(screen.getByText('Compared with current'));
    expect(screen.getByText('Senior Coder')).toBeInTheDocument();
  });

  it('reverts after confirming, and tells the page to reload', async () => {
    const onReverted = vi.fn();
    const revert = vi.fn<(body: unknown) => EntityVersion>(() =>
      version({ id: 13, number: 3, event: 'reverted', restoredFromNumber: 1 }),
    );
    answerFetch({
      [`GET ${listPath}`]: {
        versions: [version({ id: 12, number: 2 }), version({ id: 11, number: 1 })],
        nextBefore: null,
        currentVersionNumber: 2,
      },
      [`GET ${listPath}/11`]: detail({}),
      [`POST ${listPath}/11/revert`]: (init?: RequestInit) => revert(JSON.parse(String(init?.body))),
    });

    renderDrawer({ onReverted });
    await userEvent.click(await screen.findByRole('button', { name: /v1 Saved/ }));
    await userEvent.click(await screen.findByRole('button', { name: 'Revert to v1' }));
    const dialog = await screen.findByRole('dialog', { name: 'Revert to v1?' });
    await userEvent.click(within(dialog).getByRole('button', { name: 'Revert' }));

    expect(await screen.findByText('Reverted to v1 — saved as v3')).toBeInTheDocument();
    expect(revert).toHaveBeenCalledWith({ base_version: 2 });
    expect(onReverted).toHaveBeenCalled();
  });

  it('says so when someone saved in between', async () => {
    answerFetch({
      [`GET ${listPath}`]: {
        versions: [version({ id: 12, number: 2 }), version({ id: 11, number: 1 })],
        nextBefore: null,
        currentVersionNumber: 2,
      },
      [`GET ${listPath}/11`]: detail({}),
      [`POST ${listPath}/11/revert`]: jsonResponse(
        { error: 'Someone else saved a newer version (v3).', currentVersionNumber: 3 },
        409,
      ),
    });

    renderDrawer();
    await userEvent.click(await screen.findByRole('button', { name: /v1 Saved/ }));
    await userEvent.click(await screen.findByRole('button', { name: 'Revert to v1' }));
    await userEvent.click(
      within(await screen.findByRole('dialog', { name: 'Revert to v1?' })).getByRole('button', { name: 'Revert' }),
    );

    expect(await screen.findByText('Someone else saved a newer version (v3).')).toBeInTheDocument();
  });

  it('offers no revert without write access', async () => {
    answerFetch({
      [`GET ${listPath}`]: {
        versions: [version({ id: 12, number: 2 }), version({ id: 11, number: 1 })],
        nextBefore: null,
        currentVersionNumber: 2,
      },
      [`GET ${listPath}/11`]: detail({}),
    });

    renderDrawer({ canRevert: false });
    await userEvent.click(await screen.findByRole('button', { name: /v1 Saved/ }));
    await screen.findByText('Coder');

    expect(screen.queryByRole('button', { name: 'Revert to v1' })).not.toBeInTheDocument();
  });

  it('loads older versions on demand', async () => {
    const fetch = answerFetch({
      [`GET ${listPath}`]: (init?: RequestInit) => init,
    });
    fetch.mockImplementation(async (input) =>
      String(input).includes('before=')
        ? jsonResponse({
            versions: [version({ id: 1, number: 1, event: 'created' })],
            nextBefore: null,
            currentVersionNumber: 21,
          })
        : jsonResponse({ versions: [version({ id: 21, number: 21 })], nextBefore: 21, currentVersionNumber: 21 }),
    );

    renderDrawer();
    await userEvent.click(await screen.findByRole('button', { name: 'Load older versions' }));

    expect(await screen.findByText('Created')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Load older versions' })).not.toBeInTheDocument();
  });
});

describe('revertWarnings', () => {
  it('warns that moving an MCP server resets its secrets, and names keys to set again', () => {
    const target = {
      url: 'https://old.example',
      transport: 'http',
      secrets: { headers: { Authorization: 'hmac:1' }, env: {} },
    };
    const current = { url: 'https://new.example', transport: 'http', secrets: { headers: {}, env: {} } };

    const warnings = revertWarnings('MCPServer', target, current, {});

    expect(warnings[0]).toMatch(/another address/);
    expect(warnings[1]).toMatch(/set Authorization again/);
  });

  it('names archived resources a workflow version would bring back', () => {
    const target = { config: {}, steps: [{ id: 1, tool_ids: [4] }] };

    const warnings = revertWarnings('Workflow', target, {}, { Tool: { '4': { name: 'Deployer', archived: true } } });

    expect(warnings).toEqual([expect.stringMatching(/Deployer/)]);
  });
});
