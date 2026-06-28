import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { AgentFormModal } from './AgentFormModal';

// AgentFormModal uses Mantine's own useForm (with a zod resolver), not Inertia's useForm, so the
// real validation runs here. A valid submit fires router.post (create) or router.patch (edit) —
// both are spies from the harness — and an invalid submit is blocked by the resolver.
const editAgent = {
  id: 7,
  name: 'analyst',
  title: 'Business Analyst',
  icon: '🔍',
  persona: 'Senior analyst with deep market expertise.',
  communicationStyle: 'Precise and clear.',
  principles: 'Ground findings in evidence.',
};

describe('AgentFormModal', () => {
  it('renders the create-mode title, fields, and Create button', () => {
    renderPage(<AgentFormModal opened onClose={vi.fn()} basePath="/projects/1/agents" />);

    expect(screen.getByText('Create Agent')).toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: /name/i })).toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: /title/i })).toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: /persona/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Create' })).toBeInTheDocument();
  });

  it('renders edit mode with the prefilled values, an Edit title, and a disabled name field', () => {
    renderPage(<AgentFormModal opened onClose={vi.fn()} editAgent={editAgent} basePath="/projects/1/agents" />);

    expect(screen.getByText('Edit Agent')).toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: /name/i })).toHaveValue('analyst');
    expect(screen.getByRole('textbox', { name: /title/i })).toHaveValue('Business Analyst');
    expect(screen.getByRole('textbox', { name: /name/i })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Save' })).toBeInTheDocument();
  });

  it('fires router.post with the form payload on a valid create submit', async () => {
    renderPage(<AgentFormModal opened onClose={vi.fn()} basePath="/projects/1/agents" />);

    await userEvent.type(screen.getByRole('textbox', { name: /name/i }), 'my_agent');
    await userEvent.type(screen.getByRole('textbox', { name: /title/i }), 'My Agent');
    await userEvent.type(screen.getByRole('textbox', { name: /persona/i }), 'A helpful agent.');

    await userEvent.click(screen.getByRole('button', { name: 'Create' }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith(
        '/projects/1/agents',
        expect.objectContaining({
          agent: expect.objectContaining({ name: 'my_agent', title: 'My Agent', persona: 'A helpful agent.' }),
        }),
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
  });

  it('sanitizes the name field to lowercase letters, digits, and underscores as the user types', async () => {
    renderPage(<AgentFormModal opened onClose={vi.fn()} basePath="/projects/1/agents" />);

    const nameInput = screen.getByRole('textbox', { name: /name/i });
    await userEvent.type(nameInput, 'My Agent!');

    // handleNameChange lowercases and replaces every disallowed char with an underscore.
    expect(nameInput).toHaveValue('my_agent_');
    // No submit was attempted, so nothing hit the backend.
    expect(router.post).not.toHaveBeenCalled();
  });

  it('calls onClose when Cancel is clicked', async () => {
    const onClose = vi.fn();
    renderPage(<AgentFormModal opened onClose={onClose} basePath="/projects/1/agents" />);

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    expect(onClose).toHaveBeenCalled();
  });

  it('fires router.patch to the agent path with the full payload on a valid edit save', async () => {
    renderPage(<AgentFormModal opened onClose={vi.fn()} editAgent={editAgent} basePath="/projects/1/agents" />);

    await userEvent.click(screen.getByRole('button', { name: 'Save' }));

    await waitFor(() =>
      expect(router.patch).toHaveBeenCalledWith(
        '/projects/1/agents/7',
        expect.objectContaining({
          agent: expect.objectContaining({
            name: 'analyst',
            title: 'Business Analyst',
            icon: '🔍',
            persona: 'Senior analyst with deep market expertise.',
            communicationStyle: 'Precise and clear.',
            principles: 'Ground findings in evidence.',
          }),
        }),
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
    // An edit must never go through the create endpoint.
    expect(router.post).not.toHaveBeenCalled();
  });

  it('renders duplicate mode with a Duplicate title and copy-suffixed prefilled values', () => {
    renderPage(<AgentFormModal opened onClose={vi.fn()} duplicateAgent={editAgent} basePath="/projects/1/agents" />);

    expect(screen.getByText('Duplicate Agent')).toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: /name/i })).toHaveValue('analyst_copy');
    expect(screen.getByRole('textbox', { name: /title/i })).toHaveValue('Business Analyst (Copy)');
    // Duplicate is a create flow, so the name field is editable and the primary button is Create.
    expect(screen.getByRole('textbox', { name: /name/i })).not.toBeDisabled();
    expect(screen.getByRole('button', { name: 'Create' })).toBeInTheDocument();
  });

  it('fires router.post (not patch) when saving a duplicated agent', async () => {
    renderPage(<AgentFormModal opened onClose={vi.fn()} duplicateAgent={editAgent} basePath="/projects/1/agents" />);

    await userEvent.click(screen.getByRole('button', { name: 'Create' }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith(
        '/projects/1/agents',
        expect.objectContaining({
          agent: expect.objectContaining({ name: 'analyst_copy', title: 'Business Analyst (Copy)' }),
        }),
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
    expect(router.patch).not.toHaveBeenCalled();
  });

  it('shows the Icon placeholder in create mode and the agent emoji in edit mode', () => {
    const { unmount } = renderPage(<AgentFormModal opened onClose={vi.fn()} basePath="/projects/1/agents" />);
    expect(screen.getByText('Icon')).toBeInTheDocument();
    unmount();

    renderPage(<AgentFormModal opened onClose={vi.fn()} editAgent={editAgent} basePath="/projects/1/agents" />);
    expect(screen.getByText('🔍')).toBeInTheDocument();
    expect(screen.queryByText('Icon')).not.toBeInTheDocument();
  });
});
