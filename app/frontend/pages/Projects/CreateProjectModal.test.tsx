import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { makeFormStub, renderPage, screen, userEvent, within } from 'test/renderPage';

import { CreateProjectModal } from './CreateProjectModal';

describe('Projects/CreateProjectModal', () => {
  it('renders the form fields and actions when opened', () => {
    renderPage(<CreateProjectModal opened onClose={vi.fn()} />);

    const dialog = screen.getByRole('dialog');
    expect(within(dialog).getByText('Create New Project')).toBeInTheDocument();
    expect(within(dialog).getByRole('textbox', { name: 'Project Name' })).toBeInTheDocument();
    expect(within(dialog).getByRole('textbox', { name: 'Description' })).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Create' })).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Cancel' })).toBeInTheDocument();
  });

  it('does not render the modal content when closed', () => {
    renderPage(<CreateProjectModal opened={false} onClose={vi.fn()} />);

    expect(screen.queryByText('Create New Project')).not.toBeInTheDocument();
  });

  it('disables the Create button when the name is empty', () => {
    const form = makeFormStub({ name: '', description: '' });
    renderPage(<CreateProjectModal opened onClose={vi.fn()} />, { form });

    expect(screen.getByRole('button', { name: 'Create' })).toBeDisabled();
  });

  it('disables the Create button when the name is only whitespace', () => {
    const form = makeFormStub({ name: '   ', description: '' });
    renderPage(<CreateProjectModal opened onClose={vi.fn()} />, { form });

    expect(screen.getByRole('button', { name: 'Create' })).toBeDisabled();
  });

  it('submits to the projects endpoint with valid data', async () => {
    const form = makeFormStub({ name: 'Onboarding Revamp', description: 'A fresh start' });
    renderPage(<CreateProjectModal opened onClose={vi.fn()} />, { form });

    const createButton = screen.getByRole('button', { name: 'Create' });
    expect(createButton).toBeEnabled();
    await userEvent.click(createButton);

    expect(form.transform).toHaveBeenCalled();
    expect(form.post).toHaveBeenCalledWith(
      '/company/projects',
      expect.objectContaining({ onSuccess: expect.any(Function) }),
    );
  });

  it('resets, clears errors and closes when Cancel is clicked', async () => {
    const onClose = vi.fn();
    const form = makeFormStub({ name: 'Draft', description: '' });
    renderPage(<CreateProjectModal opened onClose={onClose} />, { form });

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(form.reset).toHaveBeenCalled();
    expect(form.clearErrors).toHaveBeenCalled();
    expect(onClose).toHaveBeenCalledTimes(1);
    expect(form.post).not.toHaveBeenCalled();
  });

  it('shows a validation error alert when the name field has an error', () => {
    const form = makeFormStub({ name: '', description: '' });
    form.errors = { name: 'Name has already been taken' } as Record<string, string>;
    renderPage(<CreateProjectModal opened onClose={vi.fn()} />, { form });

    // The message renders both in the dismissible Alert (role=alert) and on the TextInput's error,
    // so scope the assertion to the alert to avoid a multiple-match throw.
    expect(within(screen.getByRole('alert')).getByText('Name has already been taken')).toBeInTheDocument();
  });
});
