import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen } from 'test/renderPage';

import { DomainVerification } from './DomainVerification';

const unverified = {
  emailDomain: 'acme-robotics.example',
  domainVerifiedAt: null,
  verificationHost: '_aixle-challenge.acme-robotics.example',
  verificationRecord: 'aixle-domain-verification=abc123',
};

describe('DomainVerification', () => {
  // Signing up proved a mailbox at the domain; letting every later arrival in is
  // a claim on the domain itself, and only its owner can publish a record.
  it('gives the record to publish and where to publish it', () => {
    renderPage(<DomainVerification joining={unverified} isAdmin />);

    expect(screen.getByText('_aixle-challenge.acme-robotics.example')).toBeInTheDocument();
    expect(screen.getByText('aixle-domain-verification=abc123')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Check now' })).toBeInTheDocument();
  });

  it('says plainly what is withheld until then', () => {
    renderPage(<DomainVerification joining={unverified} isAdmin />);

    expect(screen.getByText(/everyone joins by invitation/)).toBeInTheDocument();
  });

  it('stops asking once the record is found', () => {
    renderPage(<DomainVerification joining={{ ...unverified, domainVerifiedAt: '2026-09-29T10:00:00Z' }} isAdmin />);

    expect(screen.getByText(/Domain verified/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Check now' })).not.toBeInTheDocument();
  });

  // A member can see where the workspace stands without being offered a button
  // the server would refuse.
  it('offers no button to somebody who may not press it', () => {
    renderPage(<DomainVerification joining={unverified} isAdmin={false} />);

    expect(screen.getByText('_aixle-challenge.acme-robotics.example')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Check now' })).not.toBeInTheDocument();
  });

  // A workspace with no domain has nothing to prove and nothing to show.
  it('is not drawn without a domain', () => {
    renderPage(<DomainVerification joining={{ ...unverified, emailDomain: null }} isAdmin />);

    expect(screen.queryByText(/_aixle-challenge/)).not.toBeInTheDocument();
  });
});
