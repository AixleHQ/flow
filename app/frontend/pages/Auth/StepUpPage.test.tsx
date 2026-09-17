import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { makeFormStub, renderPage, screen, userEvent } from 'test/renderPage';

import StepUpPage from './StepUpPage';

const methods = [
  { kind: 'password', name: 'Password' },
  { kind: 'google', name: 'Google' },
];

describe('StepUpPage', () => {
  it('names the methods the company still accepts', () => {
    renderPage(<StepUpPage company_name="Acme" methods={methods} />, { form: makeFormStub({ password: '' }) });

    expect(screen.getByText(/Acme accepts Password, Google for entry/)).toBeInTheDocument();
  });

  it('posts the password to /step_up', async () => {
    const form = makeFormStub({ password: 'secret' });
    renderPage(<StepUpPage company_name="Acme" methods={methods} />, { form });

    await userEvent.click(screen.getByRole('button', { name: 'Confirm' }));

    expect(form.post).toHaveBeenCalledWith('/step_up');
  });

  it('offers no password form when the company no longer accepts passwords', () => {
    renderPage(<StepUpPage company_name="Acme" methods={[{ kind: 'google', name: 'Google' }]} />, {
      form: makeFormStub({ password: '' }),
    });

    expect(screen.queryByRole('button', { name: 'Confirm' })).not.toBeInTheDocument();
    expect(screen.getByText(/Ask an administrator of Acme/)).toBeInTheDocument();
  });

  it('surfaces a refused step-up', () => {
    renderPage(<StepUpPage company_name="Acme" methods={methods} error="invalid_credentials" />, {
      form: makeFormStub({ password: '' }),
    });

    expect(screen.getByText('That password did not match. Please try again.')).toBeInTheDocument();
  });
});
