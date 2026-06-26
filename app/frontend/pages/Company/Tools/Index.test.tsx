import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import type { Tool } from 'shared/resources/tools/ToolsContent';

import ToolsIndex from './Index';

const tool = (overrides: Partial<Tool> = {}): Tool => ({
  id: 1,
  name: 'web_scraper',
  displayName: 'Web Scraper',
  description: 'Scrapes pages',
  kind: 'custom',
  scopeType: 'Company',
  scopeId: 10,
  dockerImage: 'python:3.11-slim',
  command: 'python /app/run.py',
  requiredConfigItems: [],
  inputSchema: {},
  enabled: true,
  platformTool: false,
  scopeIndicator: 'company',
  toolFiles: [],
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

describe('Company/Tools/Index', () => {
  it('renders the page heading and the primary Add Tool action', () => {
    renderAuthedPage(<ToolsIndex tools={[]} configItemNames={[]} />);

    expect(screen.getByText('Company Tools')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add Tool' })).toBeInTheDocument();
  });

  it('lists custom tools and filters them by the search query', async () => {
    renderAuthedPage(
      <ToolsIndex
        tools={[
          tool({ id: 1, name: 'web_scraper', displayName: 'Web Scraper' }),
          tool({ id: 2, name: 'pdf_parser', displayName: 'PDF Parser' }),
        ]}
        configItemNames={[]}
      />,
    );

    expect(screen.getByText('Web Scraper')).toBeInTheDocument();
    expect(screen.getByText('PDF Parser')).toBeInTheDocument();

    await userEvent.type(screen.getByPlaceholderText('Search by name...'), 'pdf');

    expect(screen.queryByText('Web Scraper')).not.toBeInTheDocument();
    expect(screen.getByText('PDF Parser')).toBeInTheDocument();
  });

  it('shows the no-match empty state when the search matches nothing', async () => {
    renderAuthedPage(<ToolsIndex tools={[tool({ displayName: 'Web Scraper' })]} configItemNames={[]} />);

    await userEvent.type(screen.getByPlaceholderText('Search by name...'), 'zzz');

    expect(screen.getByText('No tools match your filters')).toBeInTheDocument();
  });

  it('opens the Create Tool modal when Add Tool is clicked', async () => {
    renderAuthedPage(<ToolsIndex tools={[tool()]} configItemNames={[]} />);

    await userEvent.click(screen.getByRole('button', { name: 'Add Tool' }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Create Tool')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Create' })).toBeInTheDocument();
  });
});
