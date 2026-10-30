import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { makeFormStub, renderPage, screen, userEvent } from 'test/renderPage';

import MarketplaceProposalPage from './ProposalPage';

describe('MarketplaceProposalPage', () => {
  it('says what confirming does, and to which workspace', () => {
    renderPage(<MarketplaceProposalPage token="t" email="dana@northwind.example" />);

    expect(screen.getByText('dana@northwind.example')).toBeInTheDocument();
    expect(screen.getByText('northwind.example')).toBeInTheDocument();
  });

  // Opening the page raises nothing; only the button does, by POST, so that a
  // mail scanner fetching the link has asked nobody.
  it('raises the request only on the button, by POST', async () => {
    const form = makeFormStub({ token: 't' });
    renderPage(<MarketplaceProposalPage token="t" email="dana@northwind.example" />, { form });

    expect(form.post).not.toHaveBeenCalled();
    await userEvent.click(screen.getByRole('button', { name: 'Confirm the request' }));

    expect(form.post).toHaveBeenCalledWith('/marketplace/aws/proposal/confirm');
  });
});
