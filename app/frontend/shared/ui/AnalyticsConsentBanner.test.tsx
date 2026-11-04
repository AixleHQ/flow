import '@testing-library/jest-dom/vitest';
import { act } from 'react';
import { afterEach, describe, expect, it } from 'vitest';

import { buildSharedAnalytics } from 'test/factories/sharedProps';
import { renderPage, screen, userEvent } from 'test/renderPage';

import { syncAnalytics } from 'shared/lib/analytics';

import { AnalyticsConsentBanner } from './AnalyticsConsentBanner';

const show = (analytics: ReturnType<typeof buildSharedAnalytics> | null) =>
  act(() => syncAnalytics({ component: 'Auth/LoginPage', url: '/login', props: { analytics } }));

afterEach(() => {
  document.cookie = 'analytics_consent=; Path=/; Max-Age=0';
});

describe('AnalyticsConsentBanner', () => {
  it('says what is collected and links the privacy policy', () => {
    show(buildSharedAnalytics());
    renderPage(<AnalyticsConsentBanner />, { props: {} });

    const banner = screen.getByRole('dialog', { name: 'We use analytics to improve Aixle Flow' });
    expect(banner).toHaveTextContent('Profile → Privacy');
    expect(screen.getByRole('link', { name: 'Privacy Policy' })).toBeInTheDocument();
  });

  it('goes away once declined', async () => {
    show(buildSharedAnalytics());
    renderPage(<AnalyticsConsentBanner />, { props: {} });

    await userEvent.click(screen.getByRole('button', { name: 'Decline' }));

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('is not shown where analytics cannot run', () => {
    show(null);
    renderPage(<AnalyticsConsentBanner />, { props: {} });

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });
});
