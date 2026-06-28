import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { ToolFileEditor } from './ToolFileEditor';

// ToolFileEditor is a controlled CodeMirror wrapper: it takes value/onChange/path
// directly as props (no usePage/useForm), so renderPage with plain props is enough.
describe('ToolFileEditor', () => {
  it('renders the "Content" label and the editor surface', () => {
    const { container } = renderPage(<ToolFileEditor value="hello world" onChange={vi.fn()} path="notes.md" />);

    expect(screen.getByText('Content')).toBeInTheDocument();
    // CodeMirror mounts a contenteditable editor region into the DOM.
    expect(container.querySelector('.cm-editor')).toBeInTheDocument();
  });

  it('shows the provided value inside the editor', () => {
    // A plain .txt path gets no language extension, so CodeMirror keeps the line as a single
    // text node (syntax-highlighted languages split a line into many tokenized <span>s).
    renderPage(<ToolFileEditor value="just some plain text" onChange={vi.fn()} path="readme.txt" />);

    expect(screen.getByText('just some plain text')).toBeInTheDocument();
  });

  it('fires onChange when the user edits the content', async () => {
    const onChange = vi.fn();
    const { container } = renderPage(<ToolFileEditor value="" onChange={onChange} path="empty.txt" />);

    const content = container.querySelector<HTMLElement>('.cm-content');
    expect(content).not.toBeNull();

    await userEvent.type(content as HTMLElement, 'x');

    await waitFor(() => expect(onChange).toHaveBeenCalled());
  });

  it('renders an empty editor without crashing when value is blank', () => {
    const { container } = renderPage(<ToolFileEditor value="" onChange={vi.fn()} path="config.yml" />);

    expect(screen.getByText('Content')).toBeInTheDocument();
    expect(container.querySelector('.cm-editor')).toBeInTheDocument();
  });
});
