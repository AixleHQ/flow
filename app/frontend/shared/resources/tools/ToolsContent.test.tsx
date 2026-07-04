import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderPage, screen, userEvent, within } from 'test/renderPage';

import { ToolsContent, type Tool } from './ToolsContent';

function makeTool(overrides: Partial<Tool> = {}): Tool {
  return {
    id: 1,
    name: 'pdf_reader',
    displayName: 'PDF Reader',
    description: 'Reads PDFs',
    source: 'db',
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
  };
}

const baseProps = {
  configItemNames: ['API_KEY'],
  basePath: '/company/tools',
  title: 'Company Tools',
  subtitle: 'Custom tools available to your company',
  // editableScopeIndicator defaults to 'company', matching our fixtures' scopeIndicator.
};

describe('ToolsContent', () => {
  it('renders title, subtitle and a row per seeded custom tool', () => {
    renderPage(
      <ToolsContent
        {...baseProps}
        tools={[
          makeTool({ id: 1, name: 'pdf_reader', displayName: 'PDF Reader' }),
          makeTool({ id: 2, name: 'csv_parser', displayName: 'CSV Parser' }),
        ]}
      />,
    );

    expect(screen.getByText('Company Tools')).toBeInTheDocument();
    expect(screen.getByText('Custom tools available to your company')).toBeInTheDocument();
    expect(screen.getByText('PDF Reader')).toBeInTheDocument();
    expect(screen.getByText('csv_parser')).toBeInTheDocument();
  });

  it('shows the no-results empty state when no tool matches the active filter', () => {
    // Default sourceFilter is 'db', so a platform tool is filtered out -> empty list with a
    // filter active, which renders the "no tools match your filters" message.
    renderPage(<ToolsContent {...baseProps} tools={[makeTool({ source: 'code' })]} />);

    expect(screen.getByText('No tools match your filters')).toBeInTheDocument();
  });

  it('shows platform tools when the Platform filter is selected', async () => {
    renderPage(
      <ToolsContent
        {...baseProps}
        tools={[
          makeTool({ source: 'code', displayName: 'Coder SSH Exec' }),
          makeTool({ id: 2, displayName: 'My Linter' }),
        ]}
      />,
    );

    expect(screen.queryByText('Coder SSH Exec')).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('radio', { name: 'Platform' }));

    expect(screen.getByText('Coder SSH Exec')).toBeInTheDocument();
    expect(screen.queryByText('My Linter')).not.toBeInTheDocument();
  });

  it('narrows the list as the user searches by name', async () => {
    renderPage(
      <ToolsContent
        {...baseProps}
        tools={[
          makeTool({ id: 1, name: 'pdf_reader', displayName: 'PDF Reader' }),
          makeTool({ id: 2, name: 'csv_parser', displayName: 'CSV Parser' }),
        ]}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText(/search by name/i), 'csv');

    expect(screen.getByText('CSV Parser')).toBeInTheDocument();
    expect(screen.queryByText('PDF Reader')).not.toBeInTheDocument();
  });

  it('opens the create modal when "Add Tool" is clicked', async () => {
    renderPage(<ToolsContent {...baseProps} tools={[]} />);

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /add tool/i }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Create Tool')).toBeInTheDocument();
  });

  // The edit/delete row actions are icon-only ActionIcons (wrapped in Tooltips) with no accessible
  // name in jsdom, so we locate them via their Tabler icon SVG and click the enclosing <button>.
  function clickIconButton(container: HTMLElement, iconClass: string) {
    const svg = container.querySelector(`svg.${iconClass}`);
    if (!svg) throw new Error(`icon ${iconClass} not found`);
    const button = svg.closest('button');
    if (!button) throw new Error(`button for ${iconClass} not found`);
    return userEvent.click(button);
  }

  it('opens the edit modal for an editable tool', async () => {
    const { container } = renderPage(<ToolsContent {...baseProps} tools={[makeTool({ displayName: 'PDF Reader' })]} />);

    await clickIconButton(container, 'tabler-icon-edit');

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Edit Tool')).toBeInTheDocument();
  });

  it('confirming the delete modal fires router.delete to the tool path', async () => {
    const { container } = renderPage(
      <ToolsContent {...baseProps} tools={[makeTool({ id: 42, displayName: 'PDF Reader' })]} />,
    );

    await clickIconButton(container, 'tabler-icon-trash');

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Delete Tool')).toBeInTheDocument();

    await userEvent.click(within(dialog).getByRole('button', { name: 'Delete' }));

    expect(router.delete).toHaveBeenCalledWith('/company/tools/42', expect.objectContaining({ preserveScroll: true }));
  });
});
