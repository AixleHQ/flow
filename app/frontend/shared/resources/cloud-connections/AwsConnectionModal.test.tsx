import '@testing-library/jest-dom/vitest';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { AwsConnectionModal } from './AwsConnectionModal';

// Backendless: the device flow is three POSTs (create → poll → complete), so we drive the
// component by scripting fetch per URL. What matters functionally is that the verification
// URL is rendered exactly as the backend sent it, that polling stops on the documented
// terminal statuses, and that the account/role a user picks is what gets submitted.

const START_URL = 'https://d-abc123.awsapps.com/start';
// A per-instance portal host — NOT device.sso.<region>.amazonaws.com, which does not resolve.
const VERIFICATION_URL = 'https://ssoins-fake.us-east-1.portal.amazonaws.com/#/device?user_code=QCFK-N451';

type Reply = { status?: number; body?: unknown };

function scriptFetch(replies: { create?: Reply; poll?: Reply[]; complete?: Reply }) {
  const pollQueue = [...(replies.poll ?? [])];

  return vi.spyOn(globalThis, 'fetch').mockImplementation(async (input) => {
    const url = String(input);
    const pick = (reply: Reply | undefined): Response =>
      new Response(JSON.stringify(reply?.body ?? {}), {
        status: reply?.status ?? 200,
        headers: { 'Content-Type': 'application/json' },
      });

    if (url.includes('/poll')) return pick(pollQueue.shift());
    if (url.includes('/complete')) return pick(replies.complete);
    return pick(replies.create);
  });
}

const APPROVED = {
  body: {
    status: 'approved',
    accounts: [{ account_id: '111122223333', account_name: 'Prod', roles: ['BedrockUser'] }],
  },
};

const CREATED = {
  status: 201,
  body: { handle: 'h-1', verification_url: VERIFICATION_URL, user_code: 'QCFK-N451', interval: 1, expires_in: 600 },
};

async function fillAndContinue() {
  await userEvent.type(screen.getByLabelText(/Start URL/i), START_URL);
  await userEvent.type(screen.getByLabelText(/Identity Center region/i), 'us-west-2');
  await userEvent.click(screen.getByRole('button', { name: /Continue/i }));
}

describe('AwsConnectionModal', () => {
  beforeEach(() => {
    vi.useRealTimers();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('cannot start without both a start url and an identity center region', async () => {
    renderPage(<AwsConnectionModal opened onClose={vi.fn()} />);

    expect(screen.getByRole('button', { name: /Continue/i })).toBeDisabled();

    await userEvent.type(screen.getByLabelText(/Start URL/i), START_URL);
    expect(screen.getByRole('button', { name: /Continue/i })).toBeDisabled();

    await userEvent.type(screen.getByLabelText(/Identity Center region/i), 'us-west-2');
    expect(screen.getByRole('button', { name: /Continue/i })).toBeEnabled();
  });

  // The link is the whole point of the flow: one click, no code typing. It must be rendered
  // verbatim from the backend, never rebuilt in the browser.
  it('renders the verification link exactly as returned', async () => {
    scriptFetch({ create: CREATED, poll: [{ body: { status: 'pending', interval: 60 } }] });
    renderPage(<AwsConnectionModal opened onClose={vi.fn()} />);

    await fillAndContinue();

    const link = await screen.findByRole('link', { name: /Approve in AWS/i });
    expect(link).toHaveAttribute('href', VERIFICATION_URL);
    expect(link).toHaveAttribute('target', '_blank');
    expect(await screen.findByText('QCFK-N451')).toBeInTheDocument();
  });

  it('keeps polling while pending and shows the granted account once approved', async () => {
    // A fractional interval keeps the retry inside the assertion window; the component
    // honours whatever the backend sends.
    scriptFetch({ create: CREATED, poll: [{ body: { status: 'pending', interval: 0.01 } }, APPROVED] });
    renderPage(<AwsConnectionModal opened onClose={vi.fn()} />);

    await fillAndContinue();

    // Only the settled state is asserted: "waiting" is transient by design, and on a loaded
    // machine the retry lands before any assertion could observe it.
    expect(await screen.findByText(/Signed in/i)).toBeInTheDocument();
    expect(screen.queryByText(/Waiting for approval/i)).not.toBeInTheDocument();
  });

  // 410 is the backend telling us the handle is dead. Continuing to poll it can never
  // succeed, so the flow has to restart.
  it('restarts the flow when the authorization has expired', async () => {
    scriptFetch({ create: CREATED, poll: [{ status: 410, body: { error: 'expired_error' } }] });
    renderPage(<AwsConnectionModal opened onClose={vi.fn()} />);

    await fillAndContinue();

    expect(await screen.findByRole('alert')).toHaveTextContent(/expired/i);
    expect(screen.getByLabelText(/Start URL/i)).toBeInTheDocument();
  });

  it('submits the chosen account, role and bedrock region, then closes', async () => {
    const spy = scriptFetch({ create: CREATED, poll: [APPROVED], complete: { body: { connected: true } } });
    const onClose = vi.fn();
    const onConnected = vi.fn();
    renderPage(<AwsConnectionModal opened onClose={onClose} onConnected={onConnected} />);

    await fillAndContinue();
    await screen.findByText(/Signed in/i);
    await userEvent.click(screen.getByRole('button', { name: /^Connect$/i }));

    await waitFor(() => expect(onClose).toHaveBeenCalled());
    expect(onConnected).toHaveBeenCalled();

    const completeCall = spy.mock.calls.find(([url]) => String(url).includes('/complete'));
    expect(completeCall).toBeDefined();
    expect(JSON.parse(String(completeCall?.[1]?.body))).toEqual({
      handle: 'h-1',
      account_id: '111122223333',
      role_name: 'BedrockUser',
      region: 'us-east-1',
      profile: 'aixle-bedrock',
    });
  });

  // A repo may commit its own .claude/settings.json pinning AWS_PROFILE. Project settings
  // outrank the user settings we write, so that pin has to resolve to the profile we put in
  // ~/.aws/config — hence the name is editable.
  it('submits a profile name matching what a repo pins', async () => {
    const spy = scriptFetch({ create: CREATED, poll: [APPROVED], complete: { body: { connected: true } } });
    renderPage(<AwsConnectionModal opened onClose={vi.fn()} />);

    await fillAndContinue();
    await screen.findByText(/Signed in/i);
    const profileInput = screen.getByLabelText(/AWS profile name/i);
    await userEvent.clear(profileInput);
    await userEvent.type(profileInput, 'dbp-aixle');
    await userEvent.click(screen.getByRole('button', { name: /^Connect$/i }));

    const completeCall = spy.mock.calls.find(([url]) => String(url).includes('/complete'));
    expect(JSON.parse(String(completeCall?.[1]?.body)).profile).toBe('dbp-aixle');
  });

  it('surfaces the backend message when starting fails', async () => {
    scriptFetch({ create: { status: 422, body: { message: 'start_url is required' } } });
    renderPage(<AwsConnectionModal opened onClose={vi.fn()} />);

    await fillAndContinue();

    expect(await screen.findByRole('alert')).toHaveTextContent('start_url is required');
  });

  it('explains an identity center that grants no accounts', async () => {
    scriptFetch({ create: CREATED, poll: [{ body: { status: 'approved', accounts: [] } }] });
    renderPage(<AwsConnectionModal opened onClose={vi.fn()} />);

    await fillAndContinue();

    expect(await screen.findByText(/grants you no accounts/i)).toBeInTheDocument();
  });
});
