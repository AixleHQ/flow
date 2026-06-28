import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderPage, screen, userEvent, within } from 'test/renderPage';

import { AgentsContent, type Agent } from './AgentsContent';

const makeAgent = (overrides: Partial<Agent> = {}): Agent => ({
  id: 1,
  name: 'market_analyst',
  title: 'Market Analyst',
  icon: '📊',
  persona: 'Senior analyst with deep expertise in market research',
  communicationStyle: null,
  principles: null,
  source: 'custom',
  scopeType: 'Company',
  scopeId: 1,
  scopeIndicator: 'company',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

describe('AgentsContent', () => {
  it('renders the title, subtitle and a row per agent', () => {
    const agents = [
      makeAgent({ id: 1, name: 'market_analyst', title: 'Market Analyst' }),
      makeAgent({ id: 2, name: 'tech_writer', title: 'Tech Writer' }),
    ];

    renderPage(
      <AgentsContent agents={agents} basePath="/company/agents" title="Agents" subtitle="Manage your agents" />,
    );

    expect(screen.getByText('Agents')).toBeInTheDocument();
    expect(screen.getByText('Manage your agents')).toBeInTheDocument();
    expect(screen.getByText('Market Analyst')).toBeInTheDocument();
    expect(screen.getByText('Tech Writer')).toBeInTheDocument();
  });

  it('shows the empty state when there are no agents', () => {
    renderPage(<AgentsContent agents={[]} basePath="/company/agents" title="Agents" subtitle="Manage your agents" />);

    expect(screen.getByText('No agents yet')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /add your first agent/i })).toBeInTheDocument();
  });

  it('search narrows the list to matching agents', async () => {
    const agents = [
      makeAgent({ id: 1, name: 'market_analyst', title: 'Market Analyst' }),
      makeAgent({ id: 2, name: 'tech_writer', title: 'Tech Writer' }),
    ];

    renderPage(
      <AgentsContent agents={agents} basePath="/company/agents" title="Agents" subtitle="Manage your agents" />,
    );

    await userEvent.type(screen.getByPlaceholderText(/search by name or title/i), 'writer');

    expect(screen.getByText('Tech Writer')).toBeInTheDocument();
    expect(screen.queryByText('Market Analyst')).not.toBeInTheDocument();
  });

  it('clicking "Add Agent" opens the create form modal', async () => {
    renderPage(
      <AgentsContent agents={[makeAgent()]} basePath="/company/agents" title="Agents" subtitle="Manage your agents" />,
    );

    await userEvent.click(screen.getByRole('button', { name: /add agent/i }));

    expect(await screen.findByRole('heading', { name: 'Create Agent' })).toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: /^title$/i })).toBeInTheDocument();
  });

  it('confirming delete fires router.delete for the agent', async () => {
    const agent = makeAgent({ id: 7, name: 'market_analyst', title: 'Market Analyst' });

    renderPage(
      <AgentsContent agents={[agent]} basePath="/company/agents" title="Agents" subtitle="Manage your agents" />,
    );

    // Open the delete confirm modal via the row's Delete (trash) action.
    // The action-cell ActionIcons have no accessible name, so locate the trash button by its icon.
    const row = screen.getByText('Market Analyst').closest('tr') as HTMLElement;
    const trashButton = row.querySelector('.tabler-icon-trash')?.closest('button') as HTMLElement;
    await userEvent.click(trashButton);

    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Delete' }));

    expect(router.delete).toHaveBeenCalledWith('/company/agents/7', expect.objectContaining({ preserveScroll: true }));
  });

  it('in a project context shows the Scope column and disables actions for company-managed agents', () => {
    const companyAgent = makeAgent({ id: 1, title: 'Shared Analyst', scopeIndicator: 'company' });

    renderPage(
      <AgentsContent
        agents={[companyAgent]}
        basePath="/projects/1/agents"
        title="Agents"
        subtitle="Manage your agents"
      />,
    );

    expect(screen.getByText('Scope')).toBeInTheDocument();

    // The Edit and Delete actions are disabled for company-managed agents in a project context.
    const row = screen.getByText('Shared Analyst').closest('tr') as HTMLElement;
    const editButton = row.querySelector('.tabler-icon-edit')?.closest('button') as HTMLElement;
    const trashButton = row.querySelector('.tabler-icon-trash')?.closest('button') as HTMLElement;
    expect(editButton).toBeDisabled();
    expect(trashButton).toBeDisabled();
  });

  it('shows the "no match" empty state (without the add-first-agent button) when search matches nothing', async () => {
    const agents = [makeAgent({ id: 1, name: 'market_analyst', title: 'Market Analyst' })];

    renderPage(
      <AgentsContent agents={agents} basePath="/company/agents" title="Agents" subtitle="Manage your agents" />,
    );

    await userEvent.type(screen.getByPlaceholderText(/search by name or title/i), 'nonexistent_zzz');

    expect(screen.getByText('No agents match your search')).toBeInTheDocument();
    // The "add your first agent" CTA is only shown when there is no active search.
    expect(screen.queryByRole('button', { name: /add your first agent/i })).not.toBeInTheDocument();
  });

  it('search also matches against the agent name (not only the title)', async () => {
    const agents = [
      makeAgent({ id: 1, name: 'market_analyst', title: 'Market Analyst' }),
      makeAgent({ id: 2, name: 'tech_writer', title: 'Documentation Owner' }),
    ];

    renderPage(
      <AgentsContent agents={agents} basePath="/company/agents" title="Agents" subtitle="Manage your agents" />,
    );

    await userEvent.type(screen.getByPlaceholderText(/search by name or title/i), 'tech_writer');

    expect(screen.getByText('Documentation Owner')).toBeInTheDocument();
    expect(screen.queryByText('Market Analyst')).not.toBeInTheDocument();
  });

  it('clicking "Add your first agent" in the empty state opens the create modal', async () => {
    renderPage(<AgentsContent agents={[]} basePath="/company/agents" title="Agents" subtitle="Manage your agents" />);

    await userEvent.click(screen.getByRole('button', { name: /add your first agent/i }));

    expect(await screen.findByRole('heading', { name: 'Create Agent' })).toBeInTheDocument();
  });

  it('clicking the row Edit action opens the modal in edit mode with the name field disabled', async () => {
    const agent = makeAgent({ id: 9, name: 'market_analyst', title: 'Market Analyst' });

    renderPage(
      <AgentsContent agents={[agent]} basePath="/company/agents" title="Agents" subtitle="Manage your agents" />,
    );

    const row = screen.getByText('Market Analyst').closest('tr') as HTMLElement;
    const editButton = row.querySelector('.tabler-icon-edit')?.closest('button') as HTMLElement;
    await userEvent.click(editButton);

    expect(await screen.findByRole('heading', { name: 'Edit Agent' })).toBeInTheDocument();
    // The name is the unique identifier and cannot be changed once created.
    expect(screen.getByRole('textbox', { name: /^name$/i })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Save' })).toBeInTheDocument();
  });

  it('clicking the row Duplicate action opens the modal in duplicate mode prefilled with copy names', async () => {
    const agent = makeAgent({ id: 5, name: 'market_analyst', title: 'Market Analyst' });

    renderPage(
      <AgentsContent agents={[agent]} basePath="/company/agents" title="Agents" subtitle="Manage your agents" />,
    );

    const row = screen.getByText('Market Analyst').closest('tr') as HTMLElement;
    const copyButton = row.querySelector('.tabler-icon-copy')?.closest('button') as HTMLElement;
    await userEvent.click(copyButton);

    expect(await screen.findByRole('heading', { name: 'Duplicate Agent' })).toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: /^name$/i })).toHaveValue('market_analyst_copy');
    expect(screen.getByRole('textbox', { name: /^title$/i })).toHaveValue('Market Analyst (Copy)');
  });

  it('submitting a valid create form fires router.post with the agent payload', async () => {
    renderPage(<AgentsContent agents={[]} basePath="/company/agents" title="Agents" subtitle="Manage your agents" />);

    await userEvent.click(screen.getByRole('button', { name: /add agent/i }));
    await screen.findByRole('heading', { name: 'Create Agent' });

    await userEvent.type(screen.getByRole('textbox', { name: /^name$/i }), 'data_scientist');
    await userEvent.type(screen.getByRole('textbox', { name: /^title$/i }), 'Data Scientist');
    await userEvent.type(screen.getByRole('textbox', { name: /^persona$/i }), 'Crunches numbers all day');

    await userEvent.click(screen.getByRole('button', { name: 'Create' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/agents',
      expect.objectContaining({
        agent: expect.objectContaining({
          name: 'data_scientist',
          title: 'Data Scientist',
          persona: 'Crunches numbers all day',
        }),
      }),
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('submitting an edited agent fires router.patch against the agent id', async () => {
    const agent = makeAgent({
      id: 42,
      name: 'market_analyst',
      title: 'Market Analyst',
      persona: 'Original persona text',
    });

    renderPage(
      <AgentsContent agents={[agent]} basePath="/company/agents" title="Agents" subtitle="Manage your agents" />,
    );

    const row = screen.getByText('Market Analyst').closest('tr') as HTMLElement;
    const editButton = row.querySelector('.tabler-icon-edit')?.closest('button') as HTMLElement;
    await userEvent.click(editButton);
    await screen.findByRole('heading', { name: 'Edit Agent' });

    const titleInput = screen.getByRole('textbox', { name: /^title$/i });
    await userEvent.clear(titleInput);
    await userEvent.type(titleInput, 'Revised Market Analyst');

    await userEvent.click(screen.getByRole('button', { name: 'Save' }));

    expect(router.patch).toHaveBeenCalledWith(
      '/company/agents/42',
      expect.objectContaining({
        agent: expect.objectContaining({ title: 'Revised Market Analyst' }),
      }),
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('renders the fallback robot icon for an agent without a custom icon', () => {
    const agent = makeAgent({ id: 1, title: 'Iconless Agent', icon: null });

    renderPage(
      <AgentsContent agents={[agent]} basePath="/company/agents" title="Agents" subtitle="Manage your agents" />,
    );

    const row = screen.getByText('Iconless Agent').closest('tr') as HTMLElement;
    expect(within(row).getByText('🤖')).toBeInTheDocument();
  });

  it('in a project context keeps actions enabled for project-scoped agents', () => {
    const projectAgent = makeAgent({ id: 3, title: 'Local Helper', scopeIndicator: 'project' });

    renderPage(
      <AgentsContent
        agents={[projectAgent]}
        basePath="/projects/1/agents"
        title="Agents"
        subtitle="Manage your agents"
      />,
    );

    // The project's own scope badge renders and edit/delete remain enabled.
    expect(screen.getByText('project')).toBeInTheDocument();
    const row = screen.getByText('Local Helper').closest('tr') as HTMLElement;
    const editButton = row.querySelector('.tabler-icon-edit')?.closest('button') as HTMLElement;
    const trashButton = row.querySelector('.tabler-icon-trash')?.closest('button') as HTMLElement;
    expect(editButton).not.toBeDisabled();
    expect(trashButton).not.toBeDisabled();
  });

  it('does not render the Scope column in a company context', () => {
    const agents = [makeAgent({ id: 1, title: 'Market Analyst' })];

    renderPage(
      <AgentsContent agents={agents} basePath="/company/agents" title="Agents" subtitle="Manage your agents" />,
    );

    expect(screen.queryByText('Scope')).not.toBeInTheDocument();
  });
});
