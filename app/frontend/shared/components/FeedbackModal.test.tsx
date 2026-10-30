import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { fireEvent, makeFormStub, renderPage, screen, userEvent, within } from 'test/renderPage';

import { FeedbackModal } from './FeedbackModal';

describe('shared/components/FeedbackModal', () => {
  it('offers the three kinds of feedback, a message and what is sent along', () => {
    renderPage(<FeedbackModal opened onClose={vi.fn()} />);

    const dialog = screen.getByRole('dialog', { name: 'Send feedback' });
    expect(within(dialog).getByRole('radio', { name: 'Bug' })).toBeChecked();
    expect(within(dialog).getByRole('radio', { name: 'Feature request' })).toBeInTheDocument();
    expect(within(dialog).getByRole('radio', { name: 'Support' })).toBeInTheDocument();
    expect(within(dialog).getByRole('textbox', { name: 'Message' })).toBeInTheDocument();
    expect(within(dialog).getByText(/Your name, email and the address of this page are sent/)).toBeInTheDocument();
  });

  it('cannot be sent without a message', () => {
    const form = makeFormStub({ kind: 'bug', message: '  ', attachments: [] as File[] });
    renderPage(<FeedbackModal opened onClose={vi.fn()} />, { form });

    expect(screen.getByRole('button', { name: 'Send' })).toBeDisabled();
  });

  it('switches the kind when another is picked', async () => {
    const form = makeFormStub({ kind: 'bug', message: '', attachments: [] as File[] });
    renderPage(<FeedbackModal opened onClose={vi.fn()} />, { form });

    await userEvent.click(screen.getByRole('radio', { name: 'Feature request' }));

    expect(form.setData).toHaveBeenCalledWith('kind', 'feature_request');
  });

  it('sends the message with the page it was written on, and closes once sent', async () => {
    const onClose = vi.fn();
    const form = makeFormStub({ kind: 'support', message: 'How do I connect Jira?', attachments: [] as File[] });
    renderPage(<FeedbackModal opened onClose={onClose} />, { form });

    await userEvent.click(screen.getByRole('button', { name: 'Send' }));

    const transform = vi.mocked(form.transform as (fn: (d: object) => object) => void).mock.calls[0][0];
    expect(transform({ kind: 'support', message: 'How do I connect Jira?' })).toEqual({
      feedback: { kind: 'support', message: 'How do I connect Jira?', page_url: window.location.href },
    });
    const [url, options] = vi.mocked(form.post as (url: string, options: { onSuccess: () => void }) => void).mock
      .calls[0];
    expect(url).toBe('/company/feedback');

    options.onSuccess();
    expect(form.reset).toHaveBeenCalled();
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('shows why the server refused it', () => {
    const form = makeFormStub({ kind: 'bug', message: 'Again', attachments: [] as File[] });
    form.errors = { base: 'You have sent 10 messages in the last hour. Please try again later.' };
    renderPage(<FeedbackModal opened onClose={vi.fn()} />, { form });

    expect(screen.getByText('You have sent 10 messages in the last hour. Please try again later.')).toBeInTheDocument();
  });

  it('asks before throwing a typed message away', async () => {
    const onClose = vi.fn();
    const form = makeFormStub({ kind: 'bug', message: 'Half a thought', attachments: [] as File[] });
    renderPage(<FeedbackModal opened onClose={onClose} />, { form });

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    const discard = await screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
    expect(onClose).not.toHaveBeenCalled();
    await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));
    expect(onClose).toHaveBeenCalledTimes(1);
    expect(form.post).not.toHaveBeenCalled();
  });

  const fileOf = (name: string, bytes = 1, type = 'image/png') => {
    const file = new File(['x'], name, { type });
    Object.defineProperty(file, 'size', { value: bytes });
    return file;
  };

  it('attaches the files picked', async () => {
    const form = makeFormStub({ kind: 'bug', message: '', attachments: [] as File[] });
    renderPage(<FeedbackModal opened onClose={vi.fn()} />, { form });
    const shot = fileOf('shot.png');

    await userEvent.upload(screen.getByLabelText('Attach files'), shot);

    expect(form.setData).toHaveBeenCalledWith('attachments', [shot]);
  });

  it('attaches a screenshot pasted into the message', () => {
    const form = makeFormStub({ kind: 'bug', message: '', attachments: [] as File[] });
    renderPage(<FeedbackModal opened onClose={vi.fn()} />, { form });
    const shot = fileOf('image.png');

    fireEvent.paste(screen.getByRole('textbox', { name: 'Message' }), {
      clipboardData: { files: [shot], types: ['Files'], getData: () => '' },
    });

    expect(form.setData).toHaveBeenCalledWith('attachments', [shot]);
  });

  it('lists attached files, each removable', async () => {
    const log = fileOf('console.log', 2048, 'text/plain');
    const form = makeFormStub({ kind: 'bug', message: '', attachments: [fileOf('shot.png'), log] });
    renderPage(<FeedbackModal opened onClose={vi.fn()} />, { form });

    expect(screen.getByText('console.log')).toBeInTheDocument();
    expect(screen.getByText('2.0 KB')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Remove shot.png' }));

    expect(form.setData).toHaveBeenCalledWith('attachments', [log]);
  });

  it('turns away a file over the size limit, saying which', async () => {
    const form = makeFormStub({ kind: 'bug', message: '', attachments: [] as File[] });
    renderPage(<FeedbackModal opened onClose={vi.fn()} />, { form });

    await userEvent.upload(screen.getByLabelText('Attach files'), fileOf('recording.mov', 21 * 1024 * 1024));

    expect(await screen.findByText('recording.mov: larger than 20 MB.')).toBeInTheDocument();
    expect(form.setData).not.toHaveBeenCalledWith('attachments', expect.anything());
  });

  it('stops offering more files once five are attached', () => {
    const attachments = ['a', 'b', 'c', 'd', 'e'].map((name) => fileOf(`${name}.png`));
    const form = makeFormStub({ kind: 'bug', message: '', attachments });
    renderPage(<FeedbackModal opened onClose={vi.fn()} />, { form });

    expect(screen.getByRole('button', { name: 'Attach files' })).toBeDisabled();
  });
});
