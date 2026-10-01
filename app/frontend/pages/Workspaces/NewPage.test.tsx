import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { makeFormStub, renderPage, screen, userEvent } from 'test/renderPage';

import NewWorkspacePage from './NewPage';

const stranger = {
  freeQueueHours: 100,
  suggestedDomain: null,
  suggestedName: null,
  suggestedEmail: null,
  defaultMaxSessions: 4,
  sentTo: null,
  needsEmail: true,
};

const signedIn = {
  ...stranger,
  suggestedDomain: 'northwind-robotics.example',
  suggestedName: 'Northwind',
  needsEmail: false,
};

describe('New workspace page', () => {
  describe('a stranger', () => {
    it('asks for the address the workspace will be owned with', () => {
      renderPage(<NewWorkspacePage />, { props: stranger });

      expect(screen.getByLabelText(/Your work email/)).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Email me the link' })).toBeInTheDocument();
    });

    // The domain is never typed: a workspace may only claim the domain of the
    // address claiming it, so the form shows what it derived rather than
    // offering a field that can only be wrong.
    it('derives the domain from the address rather than asking for it', () => {
      renderPage(<NewWorkspacePage />, {
        props: { ...stranger, suggestedEmail: 'dana@northwind.example' },
      });

      expect(screen.getByText(/Everyone signing in from/)).toHaveTextContent('northwind.example');
      expect(screen.queryByLabelText(/Email domain/)).not.toBeInTheDocument();
    });

    it('says what the domain is for before there is an address to derive one from', () => {
      renderPage(<NewWorkspacePage />, { props: stranger });

      expect(screen.getByText(/claims the domain of your work email/)).toBeInTheDocument();
    });

    it('keeps the typed address in the form', async () => {
      const form = makeFormStub({ name: '', email: '', max_sessions: '4' });
      renderPage(<NewWorkspacePage />, { props: stranger, form });

      await userEvent.type(screen.getByLabelText(/Your work email/), 'd');

      expect(form.setData).toHaveBeenCalledWith('email', 'd');
    });

    it('opens on the address they typed at the sign-in screen', () => {
      renderPage(<NewWorkspacePage />, {
        props: { ...stranger, suggestedEmail: 'dana@northwind.example' },
      });

      expect(screen.getByLabelText(/Your work email/)).toHaveValue('dana@northwind.example');
      expect(screen.getByLabelText(/Workspace name/)).toHaveValue('Northwind');
    });
  });

  describe('someone already signed in', () => {
    it('does not ask for an address they have already proved', () => {
      renderPage(<NewWorkspacePage />, { props: signedIn });

      expect(screen.queryByLabelText(/Your work email/)).not.toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Create workspace' })).toBeInTheDocument();
      expect(screen.getByText(/Everyone signing in from/)).toHaveTextContent('northwind-robotics.example');
    });

    it('starts the session limit at the installation default', () => {
      renderPage(<NewWorkspacePage />, { props: signedIn });

      expect(screen.getByLabelText(/Concurrent sessions/)).toHaveValue('4');
    });

    // They have no address field, so a refusal about their address used to be
    // drawn nowhere and the form just sat there.
    it('shows a refusal about the address they were not asked for', () => {
      renderPage(<NewWorkspacePage />, {
        props: { ...signedIn, errors: { emailDomain: ['Email domain is a public email service'] } },
      });

      expect(screen.getByText('Email domain is a public email service')).toBeInTheDocument();
    });
  });

  describe('someone whose domain already has a workspace', () => {
    const claimed = (over = {}) => ({
      ...signedIn,
      claimedDomain: {
        domain: 'northwind-robotics.example',
        workspaceName: 'Northwind',
        joinMethods: ['Google', 'Northwind SSO'],
        approvalRequired: false,
        ...over,
      },
    });

    it('names the workspace and the way in, instead of a form that can only be refused', () => {
      renderPage(<NewWorkspacePage />, { props: claimed() });

      expect(screen.getByRole('heading', { name: 'Your domain already has a workspace' })).toBeInTheDocument();
      expect(screen.getByText(/belongs to the/)).toHaveTextContent(
        'northwind-robotics.example belongs to the Northwind workspace.',
      );
      expect(screen.getByText(/^Sign in with/)).toHaveTextContent(
        'Sign in with Google or Northwind SSO and you join Northwind straight away.',
      );
      expect(screen.getByText(/to invite you/)).toHaveTextContent(
        'Or ask an administrator of Northwind to invite you.',
      );
      expect(screen.queryByRole('button', { name: 'Create workspace' })).not.toBeInTheDocument();
    });

    it('says when joining waits for an administrator', () => {
      renderPage(<NewWorkspacePage />, { props: claimed({ approvalRequired: true }) });

      expect(screen.getByText(/^Sign in with/)).toHaveTextContent(
        'Sign in with Google or Northwind SSO to ask to join Northwind; one of its administrators approves the request.',
      );
    });

    it('names no workspace for a domain it has not proved, and offers only an invitation', () => {
      renderPage(<NewWorkspacePage />, { props: claimed({ workspaceName: null, joinMethods: [] }) });

      expect(screen.getByText(/already uses/)).toHaveTextContent(
        'A workspace already uses northwind-robotics.example.',
      );
      expect(screen.getByText(/to invite you/)).toHaveTextContent(
        'Ask an administrator of that workspace to invite you.',
      );
      expect(screen.queryByText(/^Sign in with/)).not.toBeInTheDocument();
      expect(screen.queryByText(/Northwind/)).not.toBeInTheDocument();
    });

    it('signs out, which is the way to the methods it names', async () => {
      renderPage(<NewWorkspacePage />, { props: claimed() });

      await userEvent.click(screen.getByRole('button', { name: 'Sign out to sign in another way' }));

      expect(router.delete).toHaveBeenCalledWith('/logout');
    });
  });

  // The contract that broke: the fields are posted NESTED under `workspace`,
  // because that is what the controller's strong parameters read and
  // wrap_parameters is off in this namespace. Posted flat, every submission came
  // back to the form with no visible reason — and both suites stayed green,
  // because each tested only its own side of the shape.
  it('posts the fields nested under workspace', async () => {
    const form = makeFormStub({ name: 'Northwind Robotics', email: 'dana@northwind.example', max_sessions: '8' });
    renderPage(<NewWorkspacePage />, { props: stranger, form });

    await userEvent.click(screen.getByRole('button', { name: 'Email me the link' }));

    expect(form.transform).toHaveBeenCalled();
    const transform = (form.transform as ReturnType<typeof vi.fn>).mock.calls[0][0] as (
      data: Record<string, unknown>,
    ) => Record<string, unknown>;
    expect(transform({ name: 'Northwind Robotics', email: 'a@b.example', max_sessions: '8' })).toEqual({
      workspace: { name: 'Northwind Robotics', email: 'a@b.example', max_sessions: '8' },
    });
    expect(form.post).toHaveBeenCalledWith('/workspace');
  });

  // Nothing exists yet at this point, and saying so is the difference between a
  // person waiting for an email and a person filling the form in again.
  it('sends them to their inbox once the link is out', () => {
    renderPage(<NewWorkspacePage />, { props: { ...stranger, sentTo: 'dana@northwind.example' } });

    expect(screen.getByRole('heading', { name: 'Check your email' })).toBeInTheDocument();
    expect(screen.getByText(/We sent a link to/)).toHaveTextContent('dana@northwind.example');
    expect(screen.queryByRole('button', { name: 'Email me the link' })).not.toBeInTheDocument();
  });

  // The keys are camelCase because Inertia's prop_transformer runs over every
  // prop, errors included, while the form posts snake_case. Reading the wrong
  // spelling here swallows the refusal and the form just sits there.
  // The form asks for a number of sessions without ever having said what they
  // cost or what is free, which is the question anyone filling it in has.
  it('says what the workspace gets before anyone asks for a card', () => {
    renderPage(<NewWorkspacePage />, { props: stranger });

    expect(screen.getByText(/queue-hours are free/)).toHaveTextContent('The first 100 queue-hours are free');
  });

  it('shows what the server refused', () => {
    renderPage(<NewWorkspacePage />, {
      props: { ...stranger, errors: { emailDomain: 'already has a workspace — ask someone there to invite you' } },
    });

    expect(screen.getByText(/already has a workspace/)).toBeInTheDocument();
  });

  it('shows a refused session limit', () => {
    renderPage(<NewWorkspacePage />, {
      props: { ...stranger, errors: { maxSessions: 'must be greater than 0' } },
    });

    expect(screen.getByText('must be greater than 0')).toBeInTheDocument();
  });

  it('shows a refusal that belongs to no single field', () => {
    renderPage(<NewWorkspacePage />, {
      props: { ...stranger, errors: { base: 'That link has expired.' } },
    });

    expect(screen.getByText('That link has expired.')).toBeInTheDocument();
  });
});
