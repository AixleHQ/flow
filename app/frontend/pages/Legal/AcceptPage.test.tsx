import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import AcceptPage, { type PendingDocument } from './AcceptPage';

const termsOfUse: PendingDocument = {
  key: 'terms_of_use',
  title: 'Terms of Use',
  version: '2026-10-30',
  updatedOn: '2026-10-30',
  acceptedBy: 'user',
  url: '/legal/terms_of_use',
};

const termsOfService: PendingDocument = {
  key: 'terms_of_service',
  title: 'Terms of Service',
  version: '2026-10-31',
  updatedOn: '2026-10-31',
  acceptedBy: 'company',
  url: '/legal/terms_of_service',
};

describe('AcceptPage', () => {
  beforeEach(() => {
    vi.mocked(router.post).mockClear();
  });

  it('asks an admin to accept the Terms of Service for the company and the Terms of Use for themselves', () => {
    renderPage(<AcceptPage companyName="Acme" documents={[termsOfUse, termsOfService]} />);

    expect(screen.getByRole('checkbox', { name: /I am authorized to bind Acme/ })).toBeInTheDocument();
    expect(screen.getByRole('checkbox', { name: /Acme has authorized me to use Aixle Flow/ })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Terms of Service' })).toHaveAttribute('href', '/legal/terms_of_service');
    expect(screen.getByRole('link', { name: 'Terms of Use' })).toHaveAttribute('target', '_blank');
  });

  it('accepts only once every document is ticked, naming the version each one showed', async () => {
    renderPage(<AcceptPage companyName="Acme" documents={[termsOfUse, termsOfService]} />);
    const accept = screen.getByRole('button', { name: 'Accept and continue' });

    await userEvent.click(screen.getByRole('checkbox', { name: /Acme has authorized me/ }));
    expect(accept).toBeDisabled();

    await userEvent.click(screen.getByRole('checkbox', { name: /I am authorized to bind Acme/ }));
    await userEvent.click(accept);

    expect(router.post).toHaveBeenCalledWith(
      '/legal/accept',
      { accepted: { terms_of_use: '2026-10-30', terms_of_service: '2026-10-31' } },
      expect.anything(),
    );
  });

  it('clears a box when the document it was ticked for changes version', async () => {
    const { rerender } = renderPage(<AcceptPage companyName="Acme" documents={[termsOfUse]} />);
    await userEvent.click(screen.getByRole('checkbox', { name: /Acme has authorized me/ }));

    rerender(<AcceptPage companyName="Acme" documents={[{ ...termsOfUse, version: '2026-12-01' }]} />);

    expect(screen.getByRole('checkbox', { name: /Acme has authorized me/ })).not.toBeChecked();
    expect(screen.getByRole('button', { name: 'Accept and continue' })).toBeDisabled();
  });

  it("shows the server's refusal", () => {
    renderPage(
      <AcceptPage
        companyName="Acme"
        documents={[termsOfUse]}
        errors={{ base: 'These terms were updated while you were reading them.' }}
      />,
    );

    expect(screen.getByRole('alert')).toHaveTextContent('These terms were updated while you were reading them.');
  });
});
