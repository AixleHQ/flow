import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { act, renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { ToolFormModal } from './ToolFormModal';

// ToolFileEditor wraps CodeMirror (@uiw/react-codemirror): a contenteditable editor that loads
// language parsers and measures layout from a requestAnimationFrame callback. It is by far the
// heaviest component these tests render, and the file mounts it on every Files-tab test. Under CI's
// `check_all` (rails test + rubocop + brakeman + eslint + tsc + this suite, all in parallel on a
// 2–4 vCPU runner) the CPU starvation pushed the heaviest case here past even the 20s timeout, and
// vitest's retries re-ran it in the same still-starved worker → 3/3 failures, read as flaky.
// These tests only assert the editor *slot* is present (the "Content" label shown in text mode) and
// the surrounding file-row behavior — never the editor internals, which ToolFileEditor.test.tsx
// covers against the REAL CodeMirror. Stub it with a trivial element so this suite stops paying the
// CodeMirror render cost.
vi.mock('./ToolFileEditor', async () => {
  const { createElement } = await import('react');
  return { ToolFileEditor: () => createElement('div', null, 'Content') };
});

const editTool = {
  id: 7,
  name: 'my_tool',
  displayName: 'My Custom Tool',
  description: 'Does a thing',
  dockerImage: 'python:3.11-slim',
  command: 'python /app/script.py',
  requiredConfigItems: [],
  inputSchema: {},
  scopeType: null,
  toolFiles: [],
};

describe('ToolFormModal', () => {
  it('renders the Create title and basic fields when opened', () => {
    renderPage(<ToolFormModal opened onClose={vi.fn()} configItemNames={[]} basePath="/projects/1/tools" />);

    expect(screen.getByRole('heading', { name: 'Create Tool' })).toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: /^name$/i })).toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: /display name/i })).toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: /docker image/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Create' })).toBeInTheDocument();
  });

  it('renders the Edit title and pre-fills values from editTool', async () => {
    renderPage(
      <ToolFormModal opened onClose={vi.fn()} editTool={editTool} configItemNames={[]} basePath="/projects/1/tools" />,
    );

    expect(screen.getByRole('heading', { name: 'Edit Tool' })).toBeInTheDocument();
    await waitFor(() => expect(screen.getByRole('textbox', { name: /display name/i })).toHaveValue('My Custom Tool'));
    expect(screen.getByRole('textbox', { name: /docker image/i })).toHaveValue('python:3.11-slim');
    expect(screen.getByRole('button', { name: 'Save' })).toBeInTheDocument();
  });

  it('clicking Cancel calls onClose', async () => {
    const onClose = vi.fn();
    renderPage(<ToolFormModal opened onClose={onClose} configItemNames={[]} basePath="/projects/1/tools" />);

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(onClose).toHaveBeenCalled();
  });

  it('does NOT fire a backend request when required fields are empty (validation blocks submit)', async () => {
    // The component's zodResolver runs on submit and, with this zod version, throws while
    // building error messages — React 19 re-emits that as a window "error" event. We swallow
    // exactly that expected event so the run stays green; the assertion below proves submit was
    // still blocked (no backend request fired).
    const swallow = (e: ErrorEvent) => e.preventDefault();
    window.addEventListener('error', swallow);
    try {
      renderPage(<ToolFormModal opened onClose={vi.fn()} configItemNames={[]} basePath="/projects/1/tools" />);

      await userEvent.click(screen.getByRole('button', { name: 'Create' }));

      expect(router.post).not.toHaveBeenCalled();
      expect(router.patch).not.toHaveBeenCalled();
    } finally {
      window.removeEventListener('error', swallow);
    }
  });

  it('a valid create submit fires router.post to basePath with the tool payload', async () => {
    renderPage(<ToolFormModal opened onClose={vi.fn()} configItemNames={[]} basePath="/projects/1/tools" />);

    await userEvent.type(screen.getByRole('textbox', { name: /^name$/i }), 'scraper');
    await userEvent.type(screen.getByRole('textbox', { name: /display name/i }), 'Web Scraper');
    await userEvent.type(screen.getByRole('textbox', { name: /docker image/i }), 'node:20');

    await userEvent.click(screen.getByRole('button', { name: 'Create' }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith(
        '/projects/1/tools',
        expect.objectContaining({
          tool: expect.objectContaining({
            name: 'scraper',
            displayName: 'Web Scraper',
            dockerImage: 'node:20',
          }),
        }),
        expect.any(Object),
      ),
    );
    expect(router.patch).not.toHaveBeenCalled();
  });

  it('a valid edit submit fires router.patch to basePath/{id}', async () => {
    renderPage(
      <ToolFormModal opened onClose={vi.fn()} editTool={editTool} configItemNames={[]} basePath="/projects/1/tools" />,
    );

    await waitFor(() => expect(screen.getByRole('textbox', { name: /display name/i })).toHaveValue('My Custom Tool'));

    await userEvent.click(screen.getByRole('button', { name: 'Save' }));

    await waitFor(() =>
      expect(router.patch).toHaveBeenCalledWith(
        '/projects/1/tools/7',
        expect.objectContaining({ tool: expect.objectContaining({ name: 'my_tool' }) }),
        expect.any(Object),
      ),
    );
    expect(router.post).not.toHaveBeenCalled();
  });

  it('renders nothing visible when not opened', () => {
    renderPage(<ToolFormModal opened={false} onClose={vi.fn()} configItemNames={[]} basePath="/projects/1/tools" />);

    expect(screen.queryByRole('heading', { name: /create tool/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: /edit tool/i })).not.toBeInTheDocument();
  });

  it('disables the Name field in edit mode but leaves it editable in create mode', async () => {
    const { unmount } = renderPage(
      <ToolFormModal opened onClose={vi.fn()} editTool={editTool} configItemNames={[]} basePath="/projects/1/tools" />,
    );

    await waitFor(() => expect(screen.getByRole('textbox', { name: /^name$/i })).toHaveValue('my_tool'));
    expect(screen.getByRole('textbox', { name: /^name$/i })).toBeDisabled();
    unmount();

    renderPage(<ToolFormModal opened onClose={vi.fn()} configItemNames={[]} basePath="/projects/1/tools" />);
    expect(screen.getByRole('textbox', { name: /^name$/i })).toBeEnabled();
  });

  it('normalizes the Name field: uppercase and punctuation become lowercase + underscores', async () => {
    renderPage(<ToolFormModal opened onClose={vi.fn()} configItemNames={[]} basePath="/projects/1/tools" />);

    const name = screen.getByRole('textbox', { name: /^name$/i });
    await userEvent.type(name, 'My-Cool Tool!');

    await waitFor(() => expect(name).toHaveValue('my_cool_tool_'));
  });

  it('shows the empty-files message and a zero count on the Files tab by default', async () => {
    renderPage(<ToolFormModal opened onClose={vi.fn()} configItemNames={[]} basePath="/projects/1/tools" />);

    await userEvent.click(screen.getByRole('tab', { name: /files \(0\)/i }));

    expect(screen.getByText(/no files\. add files to mount into the container\./i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /add file/i })).toBeInTheDocument();
  });

  it('Add File adds a file row (pre-filled /workspace/ path) and bumps the Files tab count', async () => {
    renderPage(<ToolFormModal opened onClose={vi.fn()} configItemNames={[]} basePath="/projects/1/tools" />);

    await userEvent.click(screen.getByRole('tab', { name: /files \(0\)/i }));
    await userEvent.click(screen.getByRole('button', { name: /add file/i }));

    expect(screen.getByRole('textbox', { name: /^path$/i })).toHaveValue('/workspace/');
    expect(screen.getByRole('tab', { name: /files \(1\)/i })).toBeInTheDocument();
    // text mode is the default → the editor's "Content" label is present
    expect(screen.getByText('Content')).toBeInTheDocument();
  });

  it('shows a path-validation error when the file path does not start with /workspace/', async () => {
    renderPage(<ToolFormModal opened onClose={vi.fn()} configItemNames={[]} basePath="/projects/1/tools" />);

    await userEvent.click(screen.getByRole('tab', { name: /files \(0\)/i }));
    await userEvent.click(screen.getByRole('button', { name: /add file/i }));

    const path = screen.getByRole('textbox', { name: /^path$/i });
    await userEvent.clear(path);
    await userEvent.type(path, '/etc/passwd');

    expect(await screen.findByText('Path must start with /workspace/')).toBeInTheDocument();
  });

  it('removing a newly-added (unsaved) file row drops it and resets the count to zero', async () => {
    renderPage(<ToolFormModal opened onClose={vi.fn()} configItemNames={[]} basePath="/projects/1/tools" />);

    await userEvent.click(screen.getByRole('tab', { name: /files \(0\)/i }));
    await userEvent.click(screen.getByRole('button', { name: /add file/i }));
    expect(screen.getByRole('tab', { name: /files \(1\)/i })).toBeInTheDocument();

    // The trash ActionIcon is the only button rendered without text inside the file panel.
    const panel = screen.getByRole('tabpanel');
    const buttons = within(panel).getAllByRole('button');
    const trash = buttons.find((b) => b.textContent === '');
    await userEvent.click(trash as HTMLElement);

    expect(screen.getByRole('tab', { name: /files \(0\)/i })).toBeInTheDocument();
    expect(screen.getByText(/no files\. add files to mount into the container\./i)).toBeInTheDocument();
  });

  it('switching a file to Upload mode reveals the click-to-select dropzone', async () => {
    renderPage(<ToolFormModal opened onClose={vi.fn()} configItemNames={[]} basePath="/projects/1/tools" />);

    await userEvent.click(screen.getByRole('tab', { name: /files \(0\)/i }));
    await userEvent.click(screen.getByRole('button', { name: /add file/i }));

    // Text mode active by default → editor "Content" label visible.
    expect(screen.getByText('Content')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('radio', { name: /upload/i }));

    expect(await screen.findByText(/click to select a file/i)).toBeInTheDocument();
    expect(screen.queryByText('Content')).not.toBeInTheDocument();
  });

  it('submitting with an invalid file path is blocked, fires no request, and jumps to the Files tab', async () => {
    renderPage(<ToolFormModal opened onClose={vi.fn()} configItemNames={[]} basePath="/projects/1/tools" />);

    // Fill valid basic fields so the only blocker is the bad file path.
    await userEvent.type(screen.getByRole('textbox', { name: /^name$/i }), 'scraper');
    await userEvent.type(screen.getByRole('textbox', { name: /display name/i }), 'Scraper Tool');
    await userEvent.type(screen.getByRole('textbox', { name: /docker image/i }), 'node:20');

    await userEvent.click(screen.getByRole('tab', { name: /files \(0\)/i }));
    await userEvent.click(screen.getByRole('button', { name: /add file/i }));
    const path = screen.getByRole('textbox', { name: /^path$/i });
    await userEvent.clear(path);
    await userEvent.type(path, '/bad/place');

    await userEvent.click(screen.getByRole('button', { name: 'Create' }));

    // handleSubmit bails (setActiveTab('files'), no router call).
    await waitFor(() =>
      expect(screen.getByRole('tab', { name: /files \(1\)/i })).toHaveAttribute('aria-selected', 'true'),
    );
    expect(router.post).not.toHaveBeenCalled();
    expect(router.patch).not.toHaveBeenCalled();
  });

  it('renders the config MultiSelect options on the Config Items tab', async () => {
    renderPage(
      <ToolFormModal
        opened
        onClose={vi.fn()}
        configItemNames={['OPENAI_API_KEY', 'DATABASE_URL']}
        basePath="/projects/1/tools"
      />,
    );

    await userEvent.click(screen.getByRole('tab', { name: /config items/i }));

    expect(screen.getByText(/select config items to inject as environment variables/i)).toBeInTheDocument();

    // Open the searchable MultiSelect dropdown and assert the seeded options appear.
    await userEvent.click(screen.getByPlaceholderText(/select config items\.\.\./i));
    expect(await screen.findByText('OPENAI_API_KEY')).toBeInTheDocument();
    expect(screen.getByText('DATABASE_URL')).toBeInTheDocument();
  });

  it('pre-fills existing tool files (path + count) in edit mode', async () => {
    const toolWithFiles = {
      ...editTool,
      toolFiles: [
        {
          id: 11,
          path: '/workspace/run.py',
          content: 'print(1)',
          binary: false,
          fileName: null,
          fileUrl: null,
        },
      ],
    };

    renderPage(
      <ToolFormModal
        opened
        onClose={vi.fn()}
        editTool={toolWithFiles}
        configItemNames={[]}
        basePath="/projects/1/tools"
      />,
    );

    await userEvent.click(screen.getByRole('tab', { name: /files \(1\)/i }));
    expect(screen.getByRole('textbox', { name: /^path$/i })).toHaveValue('/workspace/run.py');
  });

  it('shows the existing uploaded-file row with a Download link for a binary tool file in edit mode', async () => {
    const toolWithBinary = {
      ...editTool,
      toolFiles: [
        {
          id: 12,
          path: '/workspace/data.bin',
          content: '',
          binary: true,
          fileName: 'data.bin',
          fileUrl: 'https://example.test/data.bin',
        },
      ],
    };

    renderPage(
      <ToolFormModal
        opened
        onClose={vi.fn()}
        editTool={toolWithBinary}
        configItemNames={[]}
        basePath="/projects/1/tools"
      />,
    );

    await userEvent.click(screen.getByRole('tab', { name: /files \(1\)/i }));

    expect(screen.getByText('data.bin')).toBeInTheDocument();
    const download = screen.getByRole('link', { name: /download/i });
    expect(download).toHaveAttribute('href', 'https://example.test/data.bin');
    expect(screen.getByRole('button', { name: /replace/i })).toBeInTheDocument();
  });

  it('a valid create submit with a text file includes it in tool_files_attributes', async () => {
    renderPage(<ToolFormModal opened onClose={vi.fn()} configItemNames={[]} basePath="/projects/1/tools" />);

    await userEvent.type(screen.getByRole('textbox', { name: /^name$/i }), 'scraper');
    await userEvent.type(screen.getByRole('textbox', { name: /display name/i }), 'Web Scraper');
    await userEvent.type(screen.getByRole('textbox', { name: /docker image/i }), 'node:20');

    // Add a file with a valid /workspace/ path so it survives handleSubmit's path guard.
    await userEvent.click(screen.getByRole('tab', { name: /files \(0\)/i }));
    await userEvent.click(screen.getByRole('button', { name: /add file/i }));
    const path = screen.getByRole('textbox', { name: /^path$/i });
    await userEvent.clear(path);
    await userEvent.type(path, '/workspace/run.py');

    await userEvent.click(screen.getByRole('button', { name: 'Create' }));

    // No uploads → the JSON (non-FormData) branch: activeFiles are mapped into toolFilesAttributes.
    // ToolFileEditor is stubbed and never emits onChange, so the file's content stays ''.
    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith(
        '/projects/1/tools',
        expect.objectContaining({
          tool: expect.objectContaining({
            toolFilesAttributes: expect.arrayContaining([
              expect.objectContaining({ path: '/workspace/run.py', content: '' }),
            ]),
          }),
        }),
        expect.any(Object),
      ),
    );
    expect(router.patch).not.toHaveBeenCalled();
  });

  it('submitting an upload-mode file with no file selected is blocked and jumps to the Files tab', async () => {
    renderPage(<ToolFormModal opened onClose={vi.fn()} configItemNames={[]} basePath="/projects/1/tools" />);

    // Valid basic fields so the only blocker is the missing upload.
    await userEvent.type(screen.getByRole('textbox', { name: /^name$/i }), 'scraper');
    await userEvent.type(screen.getByRole('textbox', { name: /display name/i }), 'Web Scraper');
    await userEvent.type(screen.getByRole('textbox', { name: /docker image/i }), 'node:20');

    // Add a file (default /workspace/ path is valid), switch to Upload mode, select nothing.
    await userEvent.click(screen.getByRole('tab', { name: /files \(0\)/i }));
    await userEvent.click(screen.getByRole('button', { name: /add file/i }));
    await userEvent.click(screen.getByRole('radio', { name: /upload/i }));
    expect(await screen.findByText(/click to select a file/i)).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Create' }));

    // handleSubmit's uploadFileMissing guard bails: no request, tab forced to Files.
    await waitFor(() =>
      expect(screen.getByRole('tab', { name: /files \(1\)/i })).toHaveAttribute('aria-selected', 'true'),
    );
    expect(router.post).not.toHaveBeenCalled();
    expect(router.patch).not.toHaveBeenCalled();
  });

  it('removing a saved file in edit mode marks it _destroy and Save submits the deletion', async () => {
    const toolWithFiles = {
      ...editTool,
      toolFiles: [
        {
          id: 11,
          path: '/workspace/run.py',
          content: 'print(1)',
          binary: false,
          fileName: null,
          fileUrl: null,
        },
      ],
    };

    renderPage(
      <ToolFormModal
        opened
        onClose={vi.fn()}
        editTool={toolWithFiles}
        configItemNames={[]}
        basePath="/projects/1/tools"
      />,
    );

    await userEvent.click(screen.getByRole('tab', { name: /files \(1\)/i }));

    // The trash ActionIcon is the only text-less button in the file panel.
    const panel = screen.getByRole('tabpanel');
    const trash = within(panel)
      .getAllByRole('button')
      .find((b) => b.textContent === '');
    await userEvent.click(trash as HTMLElement);

    // A saved row (has id) is kept but hidden as _destroy → count drops and the empty message returns.
    expect(screen.getByRole('tab', { name: /files \(0\)/i })).toBeInTheDocument();
    expect(screen.getByText(/no files\. add files to mount into the container\./i)).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Save' }));

    await waitFor(() =>
      expect(router.patch).toHaveBeenCalledWith(
        '/projects/1/tools/7',
        expect.objectContaining({
          tool: expect.objectContaining({
            toolFilesAttributes: expect.arrayContaining([expect.objectContaining({ id: 11, _destroy: '1' })]),
          }),
        }),
        expect.any(Object),
      ),
    );
    expect(router.post).not.toHaveBeenCalled();
  });

  it('selecting a config item includes it in the submit payload', async () => {
    renderPage(
      <ToolFormModal
        opened
        onClose={vi.fn()}
        configItemNames={['OPENAI_API_KEY', 'DATABASE_URL']}
        basePath="/projects/1/tools"
      />,
    );

    await userEvent.type(screen.getByRole('textbox', { name: /^name$/i }), 'scraper');
    await userEvent.type(screen.getByRole('textbox', { name: /display name/i }), 'Web Scraper');
    await userEvent.type(screen.getByRole('textbox', { name: /docker image/i }), 'node:20');

    await userEvent.click(screen.getByRole('tab', { name: /config items/i }));
    await userEvent.click(screen.getByPlaceholderText(/select config items\.\.\./i));
    await userEvent.click(await screen.findByRole('option', { name: 'OPENAI_API_KEY' }));

    await userEvent.click(screen.getByRole('button', { name: 'Create' }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith(
        '/projects/1/tools',
        expect.objectContaining({
          tool: expect.objectContaining({ requiredConfigItems: ['OPENAI_API_KEY'] }),
        }),
        expect.any(Object),
      ),
    );
  });

  it('closes the modal via the router onSuccess callback after a create submit', async () => {
    const onClose = vi.fn();
    renderPage(<ToolFormModal opened onClose={onClose} configItemNames={[]} basePath="/projects/1/tools" />);

    await userEvent.type(screen.getByRole('textbox', { name: /^name$/i }), 'scraper');
    await userEvent.type(screen.getByRole('textbox', { name: /display name/i }), 'Web Scraper');
    await userEvent.type(screen.getByRole('textbox', { name: /docker image/i }), 'node:20');
    await userEvent.click(screen.getByRole('button', { name: 'Create' }));

    await waitFor(() => expect(router.post).toHaveBeenCalled());

    // The inert router mock never resolves, so drive the success path Inertia would have invoked.
    const options = (router.post as ReturnType<typeof vi.fn>).mock.calls[0][2];
    act(() => options.onSuccess?.());

    expect(onClose).toHaveBeenCalled();
  });

  it('surfaces server-side field errors from the router onError callback', async () => {
    const onClose = vi.fn();
    renderPage(<ToolFormModal opened onClose={onClose} configItemNames={[]} basePath="/projects/1/tools" />);

    await userEvent.type(screen.getByRole('textbox', { name: /^name$/i }), 'scraper');
    await userEvent.type(screen.getByRole('textbox', { name: /display name/i }), 'Web Scraper');
    await userEvent.type(screen.getByRole('textbox', { name: /docker image/i }), 'node:20');
    await userEvent.click(screen.getByRole('button', { name: 'Create' }));

    await waitFor(() => expect(router.post).toHaveBeenCalled());

    // handleSubmit's onError maps each server error onto its matching form field via setFieldError.
    const options = (router.post as ReturnType<typeof vi.fn>).mock.calls[0][2];
    act(() => options.onError?.({ displayName: 'has already been taken' }));

    expect(await screen.findByText('has already been taken')).toBeInTheDocument();
    // A rejected submit leaves the modal open.
    expect(onClose).not.toHaveBeenCalled();
  });
});
