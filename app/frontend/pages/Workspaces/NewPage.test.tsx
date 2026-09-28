import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { makeFormStub, renderPage, screen, userEvent } from 'test/renderPage';

import NewWorkspacePage from './NewPage';

const props = {
  suggestedDomain: 'northwind-robotics.example',
  suggestedName: 'Northwind',
  defaultMaxSessions: 4,
};

describe('New workspace page', () => {
  it('offers the domain the person signed in with', () => {
    renderPage(<NewWorkspacePage />, { props });

    expect(screen.getByLabelText(/Email domain/)).toHaveValue('northwind-robotics.example');
    // The domain is set apart from the sentence around it, so the claim reads as
    // one line but is not one text node.
    expect(screen.getByText(/Nobody has claimed/)).toHaveTextContent(
      'Nobody has claimed northwind-robotics.example yet, so this one is yours to start.',
    );
  });

  it('starts the session limit at the installation default', () => {
    renderPage(<NewWorkspacePage />, { props });

    expect(screen.getByLabelText(/Concurrent sessions/)).toHaveValue('4');
  });

  // The contract that broke: the fields are posted NESTED under `workspace`,
  // because that is what the controller's strong parameters read and
  // wrap_parameters is off in this namespace. Posted flat, every submission came
  // back to the form with no visible reason — and both suites stayed green,
  // because each tested only its own side of the shape.
  it('posts the fields nested under workspace', async () => {
    const form = makeFormStub({
      name: 'Northwind Robotics',
      email_domain: 'northwind-robotics.example',
      max_sessions: '8',
    });
    renderPage(<NewWorkspacePage />, { props, form });

    await userEvent.click(screen.getByRole('button', { name: 'Create workspace' }));

    expect(form.transform).toHaveBeenCalled();
    const transform = (form.transform as ReturnType<typeof vi.fn>).mock.calls[0][0] as (
      data: Record<string, unknown>,
    ) => Record<string, unknown>;
    expect(transform({ name: 'Northwind Robotics', email_domain: 'a.example', max_sessions: '8' })).toEqual({
      workspace: { name: 'Northwind Robotics', email_domain: 'a.example', max_sessions: '8' },
    });
    expect(form.post).toHaveBeenCalledWith('/workspace');
  });

  it('shows what the server refused', () => {
    renderPage(<NewWorkspacePage />, {
      props: { ...props, errors: { email_domain: 'is already verified by another workspace' } },
    });

    expect(screen.getByText(/already verified by another workspace/)).toBeInTheDocument();
  });
});
