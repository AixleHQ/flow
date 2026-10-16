import '@testing-library/jest-dom/vitest';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { answerFetch, jsonResponse } from 'test/fetchStub';
import { renderPage, screen, userEvent } from 'test/renderPage';

import BitbucketConnect from './BitbucketConnect';

const PROJECTS = [
  { id: 12, name: 'Platform', companyName: 'Acme' },
  { id: 14, name: 'Billing', companyName: 'Acme' },
];
const PREVIEW = {
  workspace: { slug: 'acme', name: 'Acme Inc' },
  expires_at: '2026-10-16T12:00:00Z',
  bound_elsewhere: false,
};

describe('Bitbucket connect page', () => {
  // window.location is read-only in jsdom; a plain object stands in, so the
  // fragment can be set and the final navigation observed.
  const originalLocation = window.location;
  const assign = vi.fn();
  const visit = (hash: string) =>
    Object.defineProperty(window, 'location', { configurable: true, writable: true, value: { hash, assign } });

  beforeEach(() => assign.mockReset());

  afterEach(() => {
    Object.defineProperty(window, 'location', { configurable: true, writable: true, value: originalLocation });
  });

  it("keeps a guest's pairing in the tab and sends them to sign in", () => {
    visit('#pairing=p1.s3cret');
    window.sessionStorage.clear();

    renderPage(<BitbucketConnect />, {
      props: { signedIn: false, loginUrl: '/login', projects: [], preselectedProjectId: null },
    });

    expect(assign).toHaveBeenCalledWith('/login');
    expect(JSON.parse(window.sessionStorage.getItem('aixle.bitbucketPairing') ?? '{}')).toEqual({
      id: 'p1',
      secret: 's3cret',
    });
  });

  it('takes the pairing back once the sign-in returns here without the fragment', async () => {
    visit('');
    window.sessionStorage.setItem('aixle.bitbucketPairing', JSON.stringify({ id: 'p1', secret: 's3cret' }));
    const sent: unknown[] = [];
    answerFetch({
      'POST /integrations/bitbucket/connect/preview': (init?: RequestInit) => {
        sent.push(JSON.parse(String(init?.body)));
        return PREVIEW;
      },
    });

    renderPage(<BitbucketConnect />, {
      props: { signedIn: true, loginUrl: '/login', projects: PROJECTS, preselectedProjectId: 12 },
    });

    expect(await screen.findByText('Acme Inc')).toBeInTheDocument();
    expect(sent).toEqual([{ pairing_id: 'p1', pairing_secret: 's3cret' }]);
    expect(window.sessionStorage.getItem('aixle.bitbucketPairing')).toBeNull();
  });

  it('previews the workspace, then connects the chosen project and goes to it', async () => {
    const user = userEvent.setup();
    visit('#pairing=p1.s3cret');
    const sent: unknown[] = [];
    answerFetch({
      'POST /integrations/bitbucket/connect/preview': (init?: RequestInit) => {
        sent.push(JSON.parse(String(init?.body)));
        return PREVIEW;
      },
      'POST /integrations/bitbucket/connect': (init?: RequestInit) => {
        sent.push(JSON.parse(String(init?.body)));
        return { redirect_url: '/company/projects/14/integrations' };
      },
    });
    renderPage(<BitbucketConnect />, {
      props: { signedIn: true, loginUrl: '/login', projects: PROJECTS, preselectedProjectId: 14 },
    });

    expect(await screen.findByText('Acme Inc')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: 'Connect' }));

    await vi.waitFor(() => expect(assign).toHaveBeenCalledWith('/company/projects/14/integrations'));
    expect(sent).toEqual([
      { pairing_id: 'p1', pairing_secret: 's3cret' },
      { pairing_id: 'p1', pairing_secret: 's3cret', project_id: 14 },
    ]);
  });

  it('waits for a project when none is preselected', async () => {
    const user = userEvent.setup();
    visit('#pairing=p1.s3cret');
    answerFetch({ 'POST /integrations/bitbucket/connect/preview': PREVIEW });
    renderPage(<BitbucketConnect />, {
      props: { signedIn: true, loginUrl: '/login', projects: PROJECTS, preselectedProjectId: null },
    });

    const connect = await screen.findByRole('button', { name: 'Connect' });
    expect(connect).toBeDisabled();
    await user.click(screen.getByRole('combobox', { name: 'Aixle project' }));
    await user.click(await screen.findByRole('option', { name: 'Platform' }));
    expect(connect).toBeEnabled();
  });

  it('says so when the link is unknown or spent', async () => {
    visit('#pairing=p1.wrong');
    answerFetch({
      'POST /integrations/bitbucket/connect/preview': jsonResponse(
        { error: 'not_found', message: 'This link is unknown, already used or expired.' },
        404,
      ),
    });
    renderPage(<BitbucketConnect />, {
      props: { signedIn: true, loginUrl: '/login', projects: PROJECTS, preselectedProjectId: null },
    });

    expect(await screen.findByText('This link is unknown, already used or expired.')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Connect' })).not.toBeInTheDocument();
  });

  it('refuses a workspace another company holds', async () => {
    visit('#pairing=p1.s3cret');
    answerFetch({ 'POST /integrations/bitbucket/connect/preview': { ...PREVIEW, bound_elsewhere: true } });
    renderPage(<BitbucketConnect />, {
      props: { signedIn: true, loginUrl: '/login', projects: PROJECTS, preselectedProjectId: 12 },
    });

    expect(await screen.findByText(/already connected to another Aixle company/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Connect' })).toBeDisabled();
  });

  it('explains where the page opens from without a pairing', () => {
    visit('');
    renderPage(<BitbucketConnect />, {
      props: { signedIn: true, loginUrl: '/login', projects: PROJECTS, preselectedProjectId: null },
    });

    expect(screen.getByText(/This page opens from Bitbucket/)).toBeInTheDocument();
  });
});
