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
  describe('what the form promises about cost', () => {
    it('offers the free allowance when there is one', () => {
      renderPage(<NewWorkspacePage />, { props: stranger });

      expect(screen.getByText(/100 worker-hours are free/)).toBeInTheDocument();
    });

    // A buyer arriving from AWS Marketplace is billed from the first minute, so
    // the allowance is not theirs to be offered.
    it('promises nothing free when nobody is giving anything away', () => {
      renderPage(<NewWorkspacePage />, { props: { ...stranger, freeQueueHours: null } });

      expect(screen.queryByText(/worker-hours are free/)).not.toBeInTheDocument();
      expect(screen.getByText(/You become its first administrator/)).toBeInTheDocument();
    });
  });

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

      expect(screen.getByLabelText(/Workers/)).toHaveValue('4');
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

    // The AWS Marketplace fulfilment page signs the buyer out on arrival, on
    // purpose: whoever pressed Subscribe in AWS is usually not whoever will use
    // the product. So this screen reaches somebody with no session at all.
    describe('and who has just paid for it through AWS Marketplace', () => {
      const buyer = (over = {}, props = {}) => ({
        ...claimed(over),
        needsEmail: true,
        freeQueueHours: null,
        marketplaceSubscription: true,
        suggestedEmail: 'dana@northwind-robotics.example',
        subscriptionRequest: null,
        ...props,
      });

      // The question they came with. Left unanswered, the screen reads as "you
      // paid and got nothing".
      it('says the subscription is held rather than lost, and offers the way to ask', () => {
        renderPage(<NewWorkspacePage />, { props: buyer() });

        expect(screen.getByText(/subscription is recorded/)).toHaveTextContent(
          'ask the administrators of Northwind to apply it',
        );
        expect(screen.getByRole('button', { name: 'Ask them to apply it' })).toBeInTheDocument();
      });

      it('names no workspace it has not proved, and still answers the question', () => {
        renderPage(<NewWorkspacePage />, { props: buyer({ workspaceName: null, joinMethods: [] }) });

        expect(screen.getByText(/subscription is recorded/)).toHaveTextContent('the workspace at your domain');
      });

      // Nothing is raised by pressing it: the address is unproved until a link
      // sent to it is opened, so this only asks for that link.
      it('asking sends a link to the address rather than raising anything', async () => {
        renderPage(<NewWorkspacePage />, { props: buyer() });

        await userEvent.click(screen.getByRole('button', { name: 'Ask them to apply it' }));

        expect(router.post).toHaveBeenCalledWith('/marketplace/aws/proposal', {
          email: 'dana@northwind-robotics.example',
        });
      });

      // The heading answers somebody who tried to create a workspace. A buyer
      // who asked for the subscription to be applied is not being refused.
      it('heads an ask under way with where it is, not with a refusal', () => {
        renderPage(<NewWorkspacePage />, { props: buyer({}, { subscriptionRequest: 'pending' }) });

        expect(screen.getByRole('heading', { name: 'Your request is with the administrators' })).toBeInTheDocument();
        expect(screen.queryByText(/no second one to create/)).not.toBeInTheDocument();
      });

      it('says a link has gone out, and that nobody has been asked yet', () => {
        renderPage(<NewWorkspacePage />, { props: buyer({}, { subscriptionRequest: 'check-email' }) });

        expect(screen.getByText(/We sent a link/)).toHaveTextContent('Nobody has been asked anything yet');
        expect(screen.queryByRole('button', { name: 'Ask them to apply it' })).not.toBeInTheDocument();
      });

      // The decision is somebody else's, and the screen should not imply the
      // subscription is doing anything in the meantime.
      it('says the request is waiting, and that nothing is billed until it is answered', () => {
        renderPage(<NewWorkspacePage />, { props: buyer({}, { subscriptionRequest: 'pending' }) });

        expect(screen.getByText(/have been asked/)).toHaveTextContent('Nothing is billed through AWS until');
      });

      it('says plainly when it was refused, and that the subscription is untouched', () => {
        renderPage(<NewWorkspacePage />, { props: buyer({}, { subscriptionRequest: 'declined' }) });

        expect(screen.getByText(/did not accept/)).toHaveTextContent('attached to nothing');
      });

      // A refusal is an answer, not the end. The buyer has paid and the
      // subscription is still attached to nothing, so a screen that tells them
      // to ask again and offers nothing to ask with strands them for good.
      it('still lets them ask again after a refusal', async () => {
        renderPage(<NewWorkspacePage />, { props: buyer({}, { subscriptionRequest: 'declined' }) });

        await userEvent.click(screen.getByRole('button', { name: 'Ask again' }));

        expect(router.post).toHaveBeenCalledWith('/marketplace/aws/proposal', {
          email: 'dana@northwind-robotics.example',
        });
      });

      it('offers the sign-in screen, because there is no session to sign out of', async () => {
        renderPage(<NewWorkspacePage />, { props: buyer() });

        expect(screen.queryByRole('button', { name: /Sign out/ })).not.toBeInTheDocument();
        await userEvent.click(screen.getByRole('button', { name: 'Go to sign in' }));

        expect(router.visit).toHaveBeenCalledWith('/login');
      });

      // Somebody signed in reaching the same screen is not a buyer and must not
      // be told anything about a subscription.
      it('says nothing about a subscription to somebody who has none', () => {
        renderPage(<NewWorkspacePage />, { props: claimed() });

        expect(screen.queryByText(/subscription is recorded/)).not.toBeInTheDocument();
      });
    });
  });

  // The contract that broke: the fields are posted NESTED under `workspace`,
  // because that is what the controller's strong parameters read and
  // wrap_parameters is off in this namespace. Posted flat, every submission came
  // back to the form with no visible reason — and both suites stayed green,
  // because each tested only its own side of the shape.
  // A buyer arriving from AWS used to be shown the form and nothing else, and
  // learned that their team already had a workspace only after typing an
  // address at its domain. The subscription has two places it can go, and the
  // page asks which.
  describe('for a buyer whose subscription has nowhere to go yet', () => {
    const buyer = (props = {}) => ({
      ...stranger,
      freeQueueHours: null,
      marketplaceSubscription: true,
      subscriptionRequest: null,
      claimedDomain: null,
      ...props,
    });

    it('asks where the subscription should go before showing any form', () => {
      renderPage(<NewWorkspacePage />, { props: buyer() });

      expect(screen.getByRole('button', { name: 'Create a new workspace' })).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Apply it to a workspace that already exists' })).toBeInTheDocument();
      expect(screen.queryByLabelText(/Workspace name/)).not.toBeInTheDocument();
    });

    it('creating opens the usual form', async () => {
      renderPage(<NewWorkspacePage />, { props: buyer() });

      await userEvent.click(screen.getByRole('button', { name: 'Create a new workspace' }));

      expect(screen.getByLabelText(/Workspace name/)).toBeInTheDocument();
    });

    // Nothing but the address: the workspace is whichever one uses its domain,
    // and the link sent there is what proves the address.
    it('applying asks only for the address, and sends the link', async () => {
      renderPage(<NewWorkspacePage />, { props: buyer() });

      await userEvent.click(screen.getByRole('button', { name: 'Apply it to a workspace that already exists' }));
      await userEvent.type(screen.getByLabelText(/Your work email at that workspace/), 'dana@northwind.example');
      await userEvent.click(screen.getByRole('button', { name: 'Email me the link' }));

      expect(router.post).toHaveBeenCalledWith(
        '/marketplace/aws/proposal',
        { email: 'dana@northwind.example' },
        expect.anything(),
      );
    });

    it('brings a refused ask back on the ask, with the address kept', () => {
      renderPage(<NewWorkspacePage />, {
        props: buyer({
          suggestedEmail: 'dana@nowhere.example',
          errors: { base: 'There is no workspace at that domain to apply it to.' },
        }),
      });

      expect(screen.getByLabelText(/Your work email at that workspace/)).toHaveValue('dana@nowhere.example');
      expect(screen.getByText('There is no workspace at that domain to apply it to.')).toBeInTheDocument();
    });
  });

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

    expect(screen.getByText(/worker-hours are free/)).toHaveTextContent('The first 100 worker-hours are free');
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
