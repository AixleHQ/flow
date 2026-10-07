import { useComputedColorScheme } from '@mantine/core';
import type { ReactNode } from 'react';

import azureDevopsLogo from './integration-logos/azure-devops.svg';
import coderDarkLogo from './integration-logos/coder-dark.svg';
import coderLogo from './integration-logos/coder.svg';
import githubDarkLogo from './integration-logos/github-dark.svg';
import githubLogo from './integration-logos/github.svg';
import gitlabLogo from './integration-logos/gitlab.svg';
import jiraLogo from './integration-logos/jira.svg';
import linearLogo from './integration-logos/linear.svg';
import slackLogo from './integration-logos/slack.svg';
import teamsLogo from './integration-logos/teams.svg';
import youtrackLogo from './integration-logos/youtrack.svg';

// GitHub and Coder publish no colored mark — their brand rules allow black or
// white only — so they carry a second file for the dark scheme.
const LOGOS: Record<string, { light: string; dark?: string }> = {
  github: { light: githubLogo, dark: githubDarkLogo },
  gitlab: { light: gitlabLogo },
  coder: { light: coderLogo, dark: coderDarkLogo },
  azure_devops: { light: azureDevopsLogo },
  jira: { light: jiraLogo },
  linear: { light: linearLogo },
  youtrack: { light: youtrackLogo },
  slack: { light: slackLogo },
  teams: { light: teamsLogo },
};

interface IntegrationLogoProps {
  provider: string | null | undefined;
  size?: number;
  /** Rendered for a provider we have no artwork for. */
  fallback?: ReactNode;
}

/**
 * The vendor's own mark for an integration provider. Every file in
 * `integration-logos/` is cropped to a square viewBox with the mark touching
 * its edges, so one `size` gives every logo the same footprint — keep that true
 * for any logo added there.
 */
export function IntegrationLogo({ provider, size = 16, fallback = null }: IntegrationLogoProps) {
  const scheme = useComputedColorScheme('dark');
  const logo = provider && Object.hasOwn(LOGOS, provider) ? LOGOS[provider] : null;
  if (!logo) return fallback;

  return (
    <img
      src={scheme === 'dark' && logo.dark ? logo.dark : logo.light}
      alt=""
      width={size}
      height={size}
      style={{ display: 'block', flex: 'none' }}
    />
  );
}
