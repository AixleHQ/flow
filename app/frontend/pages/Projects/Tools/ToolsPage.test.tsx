import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import type { Tool } from '@/types/generated';
import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import ToolsPage from './ToolsPage';

const project = { id: 7, name: 'Gateway Service' };

const makeTool = (overrides: Partial<Tool> = {}): Tool => ({
  id: 1,
  name: 'pdf_extractor',
  displayName: 'PDF Extractor',
  description: 'Extract text from PDF files',
  source: 'db',
  scopeType: 'project',
  scopeId: 7,
  dockerImage: 'registry.example.com/pdf:latest',
  command: 'python extract.py',
  requiredConfigItems: [],
  inputSchema: {},
  tags: [],
  enabled: true,
  platformTool: false,
  scopeIndicator: 'project',
  toolFiles: [],
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  currentVersionNumber: 1,
  archivedAt: null,
  ...overrides,
});

// sourceFilter defaults to 'db', so only custom tools render initially.
const tools: Tool[] = [
  makeTool({ id: 1, name: 'pdf_extractor', displayName: 'PDF Extractor' }),
  makeTool({
    id: 2,
    name: 'image_resizer',
    displayName: 'Image Resizer',
    dockerImage: null,
    toolFiles: [
      {
        id: 1,
        path: 'a.txt',
        content: 'x',
        binary: false,
        fileName: null,
        fileUrl: null,
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
      },
    ],
  }),
];

describe('Projects/Tools/ToolsPage', () => {
  it('renders the title and primary controls with seeded props', () => {
    renderAuthedPage(<ToolsPage />, { props: { project, tools, configItemNames: [] } });

    expect(screen.getByText('Wrappers')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add wrapper' })).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Search by name...')).toBeInTheDocument();
  });

  it('lists the custom tools and their docker image / built-in indicators', () => {
    renderAuthedPage(<ToolsPage />, { props: { project, tools, configItemNames: [] } });

    expect(screen.getByText('PDF Extractor')).toBeInTheDocument();
    expect(screen.getByText('pdf_extractor')).toBeInTheDocument();
    expect(screen.getByText('Image Resizer')).toBeInTheDocument();
    // tool with a dockerImage shows it; tool without one shows the Built-in badge
    expect(screen.getByText('registry.example.com/pdf:latest')).toBeInTheDocument();
    expect(screen.getByText('Built-in')).toBeInTheDocument();
  });

  it('shows the empty state when there are no tools', () => {
    // sourceFilter defaults to 'db', so hasFilters is true even before the user touches
    // anything; the empty state therefore shows the filtered message.
    renderAuthedPage(<ToolsPage />, { props: { project, tools: [], configItemNames: [] } });

    expect(screen.getByText('No wrappers match your filters')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Write your first wrapper' })).not.toBeInTheDocument();
  });

  it('filters tools by the search query (name match)', async () => {
    renderAuthedPage(<ToolsPage />, { props: { project, tools, configItemNames: [] } });

    await userEvent.type(screen.getByPlaceholderText('Search by name...'), 'image');

    expect(screen.getByText('Image Resizer')).toBeInTheDocument();
    expect(screen.queryByText('PDF Extractor')).not.toBeInTheDocument();
    // filtered empty-state message differs from the no-tools message
    expect(screen.queryByText('No wrappers yet')).not.toBeInTheDocument();
  });

  it('archives an editable project tool via the row action after confirmation', async () => {
    renderAuthedPage(<ToolsPage />, { props: { project, tools, configItemNames: [] } });

    const firstRow = screen.getByText('PDF Extractor').closest('tr') as HTMLElement;
    await userEvent.click(within(firstRow).getByRole('button', { name: 'Archive' }));

    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Archive' }));

    expect(router.delete).toHaveBeenCalledWith(
      '/company/projects/7/tools/1',
      expect.objectContaining({ preserveScroll: true }),
    );
  });
});
