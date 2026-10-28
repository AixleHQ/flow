import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen } from 'test/renderPage';

import { SettingsTabs } from './SettingsTabs';

describe('Company/Settings/SettingsTabs', () => {
  it('shows the Runners tab only while externalRunners is on', () => {
    const { unmount } = renderAuthedPage(
      <SettingsTabs active="general" companyName="Acme">
        <p>General settings</p>
      </SettingsTabs>,
    );
    expect(screen.getByRole('tab', { name: 'General' })).toBeInTheDocument();
    expect(screen.queryByRole('tab', { name: 'Runners' })).not.toBeInTheDocument();
    unmount();

    renderAuthedPage(
      <SettingsTabs active="general" companyName="Acme">
        <p>General settings</p>
      </SettingsTabs>,
      { props: { features: { externalRunners: true } } },
    );
    expect(screen.getByRole('tab', { name: 'Runners' })).toBeInTheDocument();
  });
});
