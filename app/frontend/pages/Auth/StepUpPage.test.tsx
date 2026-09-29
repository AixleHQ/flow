import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { makeFormStub, renderPage, screen, userEvent } from 'test/renderPage';

import StepUpPage from './StepUpPage';

const methods = [
  { kind: 'password', name: 'Password' },
  { kind: 'google', name: 'Google' },
];

describe('StepUpPage', () => {
  beforeEach(() => {
    vi.mocked(router.post).mockClear();
  });

  it('names the methods the company still accepts', () => {
    renderPage(<StepUpPage companyName="Acme" methods={methods} />, { form: makeFormStub({ password: '' }) });

    expect(screen.getByText(/Acme accepts Password, Google for entry/)).toBeInTheDocument();
  });

  it('posts the password to /step_up, naming the kind it is submitting', async () => {
    const form = makeFormStub({ password: 'secret', code: '' });
    renderPage(<StepUpPage companyName="Acme" methods={methods} />, { form });

    await userEvent.click(screen.getByRole('button', { name: 'Confirm' }));

    expect(router.post).toHaveBeenCalledWith(
      '/step_up',
      { step_up: { kind: 'password', password: 'secret', code: '' } },
      expect.anything(),
    );
  });

  it('posts the code as a TOTP attempt, not as an empty password', async () => {
    // The bug this pins: setData-then-post sent the PREVIOUS kind, so the code
    // form submitted as a password attempt with an empty password and always
    // failed.
    const form = makeFormStub({ password: '', code: '123456' });
    renderPage(
      <StepUpPage companyName="Acme" methods={[...methods, { kind: 'totp', name: 'Authentication codes' }]} />,
      { form },
    );

    await userEvent.click(screen.getByRole('button', { name: 'Confirm code' }));

    expect(router.post).toHaveBeenCalledWith(
      '/step_up',
      { step_up: { kind: 'totp', password: '', code: '123456' } },
      expect.anything(),
    );
  });

  it('offers no password form when the company no longer accepts passwords', () => {
    renderPage(<StepUpPage companyName="Acme" methods={[{ kind: 'google', name: 'Google' }]} />, {
      form: makeFormStub({ password: '' }),
    });

    expect(screen.queryByRole('button', { name: 'Confirm' })).not.toBeInTheDocument();
    expect(screen.getByText(/Ask an administrator of Acme/)).toBeInTheDocument();
  });

  it('surfaces a refused step-up', () => {
    renderPage(<StepUpPage companyName="Acme" methods={methods} error="invalid_credentials" />, {
      form: makeFormStub({ password: '' }),
    });

    expect(screen.getByText('That password did not match. Please try again.')).toBeInTheDocument();
  });
});
