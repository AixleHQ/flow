import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import type { Agent } from 'shared/resources/agents/AgentsContent';
import { renderAuthedPage, screen, userEvent } from 'test/renderPage';

import AgentsPage from './AgentsPage';

const project = { id: 7, name: 'Northwind' };

const agent = (overrides: Partial<Agent> = {}): Agent => ({
  id: 1,
  name: 'analyst_bot',
  title: 'Business Analyst',
  icon: '🧠',
  persona: 'Senior analyst with deep market research expertise.',
  communicationStyle: null,
  principles: null,
  source: 'project',
  scopeType: 'Project',
  scopeId: 7,
  scopeIndicator: 'project',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

describe('Projects/Agents/AgentsPage', () => {
  it('renders the heading, add CTA and a populated agent list', () => {
    renderAuthedPage(<AgentsPage />, {
      props: {
        project,
        agents: [agent({ id: 1, name: 'analyst_bot', title: 'Business Analyst' })],
      },
    });

    expect(screen.getByText('Project Agents')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add Agent' })).toBeInTheDocument();
    expect(screen.getByText('Business Analyst')).toBeInTheDocument();
    expect(screen.getByText('analyst_bot')).toBeInTheDocument();
  });

  it('shows the empty state with a create CTA when there are no agents', () => {
    renderAuthedPage(<AgentsPage />, { props: { project, agents: [] } });

    expect(screen.getByText('No agents yet')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add your first agent' })).toBeInTheDocument();
  });

  it('filters the agent list by the search query', async () => {
    renderAuthedPage(<AgentsPage />, {
      props: {
        project,
        agents: [
          agent({ id: 1, name: 'analyst_bot', title: 'Business Analyst' }),
          agent({ id: 2, name: 'dev_bot', title: 'Developer Helper' }),
        ],
      },
    });

    expect(screen.getByText('Business Analyst')).toBeInTheDocument();
    expect(screen.getByText('Developer Helper')).toBeInTheDocument();

    await userEvent.type(screen.getByPlaceholderText('Search by name or title...'), 'dev');

    expect(screen.queryByText('Business Analyst')).not.toBeInTheDocument();
    expect(screen.getByText('Developer Helper')).toBeInTheDocument();
  });

  it('shows the no-match empty state when the search matches nothing', async () => {
    renderAuthedPage(<AgentsPage />, {
      props: { project, agents: [agent({ name: 'analyst_bot', title: 'Business Analyst' })] },
    });

    await userEvent.type(screen.getByPlaceholderText('Search by name or title...'), 'zzz');

    expect(screen.getByText('No agents match your search')).toBeInTheDocument();
  });

  it('renders a scope badge for each agent in the project context', () => {
    renderAuthedPage(<AgentsPage />, {
      props: {
        project,
        agents: [agent({ id: 1, scopeIndicator: 'company' }), agent({ id: 2, scopeIndicator: 'project' })],
      },
    });

    expect(screen.getByText('company')).toBeInTheDocument();
    expect(screen.getByText('project')).toBeInTheDocument();
  });
});
