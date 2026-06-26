import '@testing-library/jest-dom/vitest';

import { router } from '@inertiajs/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import type { Agent } from 'shared/resources/agents/AgentsContent';

import AgentsIndex from './Index';

function makeAgent(overrides: Partial<Agent> = {}): Agent {
  return {
    id: 1,
    name: 'market_analyst',
    title: 'Market Analyst',
    icon: '📊',
    persona: 'Senior analyst with deep expertise in market research.',
    communicationStyle: null,
    principles: null,
    source: 'company',
    scopeType: 'Company',
    scopeId: 99,
    scopeIndicator: 'company',
    createdAt: '2026-01-01T00:00:00Z',
    updatedAt: '2026-01-01T00:00:00Z',
    ...overrides,
  };
}

describe('Company/Agents/Index', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders the heading, subtitle and Add Agent CTA', () => {
    renderAuthedPage(<AgentsIndex agents={[]} />, { props: { agents: [] } });

    expect(screen.getByText('Company Agents')).toBeInTheDocument();
    expect(
      screen.getByText('Manage company-wide agent configurations. These are available in all projects.'),
    ).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add Agent' })).toBeInTheDocument();
  });

  it('shows the empty state with a create CTA when there are no agents', () => {
    renderAuthedPage(<AgentsIndex agents={[]} />, { props: { agents: [] } });

    expect(screen.getByText('No agents yet')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add your first agent' })).toBeInTheDocument();
  });

  it('lists seeded agents and filters them by the search query', async () => {
    const agents = [
      makeAgent({ id: 1, name: 'market_analyst', title: 'Market Analyst' }),
      makeAgent({ id: 2, name: 'qa_engineer', title: 'QA Engineer' }),
    ];
    renderAuthedPage(<AgentsIndex agents={agents} />, { props: { agents } });

    expect(screen.getByText('Market Analyst')).toBeInTheDocument();
    expect(screen.getByText('QA Engineer')).toBeInTheDocument();

    await userEvent.type(screen.getByPlaceholderText('Search by name or title...'), 'market');

    expect(screen.getByText('Market Analyst')).toBeInTheDocument();
    expect(screen.queryByText('QA Engineer')).not.toBeInTheDocument();
  });

  it('shows the no-match empty state when the search matches nothing', async () => {
    const agents = [makeAgent({ id: 1, name: 'market_analyst', title: 'Market Analyst' })];
    renderAuthedPage(<AgentsIndex agents={agents} />, { props: { agents } });

    await userEvent.type(screen.getByPlaceholderText('Search by name or title...'), 'zzz');

    expect(screen.getByText('No agents match your search')).toBeInTheDocument();
    // The first-agent CTA is hidden while searching.
    expect(screen.queryByRole('button', { name: 'Add your first agent' })).not.toBeInTheDocument();
  });

  it('opens the delete modal and confirming fires router.delete with the agent path', async () => {
    const agents = [makeAgent({ id: 7, name: 'market_analyst', title: 'Market Analyst' })];
    renderAuthedPage(<AgentsIndex agents={agents} />, { props: { agents } });

    const row = screen.getByText('Market Analyst').closest('tr') as HTMLElement;
    // Row actions are ordered: Duplicate, Edit, Delete.
    const actions = within(row).getAllByRole('button');
    await userEvent.click(actions[actions.length - 1]);

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Delete Agent')).toBeInTheDocument();

    await userEvent.click(within(dialog).getByRole('button', { name: 'Delete' }));

    await waitFor(() => {
      expect(router.delete).toHaveBeenCalledWith('/company/agents/7', expect.objectContaining({ preserveScroll: true }));
    });
  });
});
