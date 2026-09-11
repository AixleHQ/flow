import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import type { AssetPickerItem } from './AssetPicker';
import { AssetPicker } from './AssetPicker';

const assets: AssetPickerItem[] = [
  { id: 1, name: 'google-credentials.json', folder: null },
  { id: 2, name: 'dashboard-metrics.json', folder: 'dashboard' },
  { id: 3, name: 'dashboard-config.yaml', folder: 'dashboard' },
  { id: 4, name: 'api-spec.md', folder: 'dashboard/specs' },
  { id: 5, name: 'kickoff-notes.docx', folder: 'initiate' },
];

function setup(over: Partial<React.ComponentProps<typeof AssetPicker>> = {}) {
  const onChange = vi.fn();
  const utils = renderPage(<AssetPicker assets={assets} value={[]} onChange={onChange} {...over} />);
  return { onChange, ...utils };
}

describe('AssetPicker', () => {
  it('shows the placeholder when nothing is selected', () => {
    setup();
    expect(screen.getByRole('button', { name: 'Select assets' })).toHaveTextContent('Select assets…');
  });

  it('shows a count once assets are selected', () => {
    setup({ value: [1, 2] });
    expect(screen.getByRole('button', { name: 'Select assets' })).toHaveTextContent('2 selected');
  });

  it('groups files by folder, with root files under Root and nested folders as their own group', async () => {
    setup();
    await userEvent.click(screen.getByRole('button', { name: 'Select assets' }));

    expect(await screen.findByText('Root')).toBeInTheDocument();
    expect(screen.getByRole('option', { name: /google-credentials\.json/ })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: /dashboard-metrics\.json/ })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: /^dashboard$/ })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: /^dashboard\/specs$/ })).toBeInTheDocument();
  });

  it('toggles a single file into the selection', async () => {
    const { onChange } = setup();
    await userEvent.click(screen.getByRole('button', { name: 'Select assets' }));
    await userEvent.click(await screen.findByRole('option', { name: /google-credentials\.json/ }));

    expect(onChange).toHaveBeenCalledWith([1]);
  });

  it('deselects an already-selected file', async () => {
    const { onChange } = setup({ value: [1] });
    await userEvent.click(screen.getByRole('button', { name: 'Select assets' }));
    await userEvent.click(await screen.findByRole('option', { name: /google-credentials\.json/ }));

    expect(onChange).toHaveBeenCalledWith([]);
  });

  it('selects every file under a folder when its header is clicked', async () => {
    const { onChange } = setup();
    await userEvent.click(screen.getByRole('button', { name: 'Select assets' }));
    await userEvent.click(await screen.findByRole('option', { name: /^dashboard$/ }));

    // dashboard's transitive files: the two directly in it, plus api-spec.md nested in dashboard/specs.
    expect(onChange).toHaveBeenCalledWith(expect.arrayContaining([2, 3, 4]));
    expect(onChange.mock.calls[0][0]).toHaveLength(3);
  });

  it('deselects every file under a folder when its fully-selected header is clicked again', async () => {
    const { onChange } = setup({ value: [1, 2, 3, 4] });
    await userEvent.click(screen.getByRole('button', { name: 'Select assets' }));
    await userEvent.click(await screen.findByRole('option', { name: /^dashboard$/ }));

    expect(onChange).toHaveBeenCalledWith([1]);
  });

  it('narrows to matching files and folders as the search box is typed into', async () => {
    setup();
    await userEvent.click(screen.getByRole('button', { name: 'Select assets' }));
    await userEvent.type(await screen.findByPlaceholderText('Search files or folders…'), 'kickoff');

    expect(screen.getByRole('option', { name: /kickoff-notes\.docx/ })).toBeInTheDocument();
    expect(screen.queryByRole('option', { name: /google-credentials/ })).not.toBeInTheDocument();
    expect(screen.queryByText('Root')).not.toBeInTheDocument();
  });

  it('says so when a search matches nothing', async () => {
    setup();
    await userEvent.click(screen.getByRole('button', { name: 'Select assets' }));
    await userEvent.type(await screen.findByPlaceholderText('Search files or folders…'), 'zzz-nonexistent');

    expect(await screen.findByText('No files or folders match "zzz-nonexistent"')).toBeInTheDocument();
  });

  it('is disabled and inert when disabled is passed', () => {
    setup({ disabled: true });
    expect(screen.getByRole('button', { name: 'Select assets' })).toBeDisabled();
  });

  it('uses the given aria-label for the trigger', () => {
    setup({ 'aria-label': 'Workflow assets' });
    expect(screen.getByRole('button', { name: 'Workflow assets' })).toBeInTheDocument();
  });
});
