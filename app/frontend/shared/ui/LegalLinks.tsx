import { usePage } from '@inertiajs/react';
import { Anchor, Group, type GroupProps } from '@mantine/core';

import { legalPrivacyPolicyPath, legalTermsOfServicePath, legalTermsOfUsePath } from 'shared/routes';

import type { SharedProps } from './types';

const DOCUMENTS = [
  { label: 'Privacy Policy', href: legalPrivacyPolicyPath },
  { label: 'Terms of Service', href: legalTermsOfServicePath },
  { label: 'Terms of Use', href: legalTermsOfUsePath },
];

/**
 * The published legal documents, for a footer. Renders nothing on an installation
 * that publishes none, where the links would lead to a 404.
 */
export function LegalLinks(props: GroupProps) {
  const { settings } = usePage<Partial<SharedProps>>().props;
  if (settings?.legalPages !== true) return null;

  return (
    <Group component="nav" aria-label="Legal" gap="md" justify="center" {...props}>
      {DOCUMENTS.map(({ label, href }) => (
        <Anchor key={label} href={href()} size="xs" c="var(--app-text-tertiary)">
          {label}
        </Anchor>
      ))}
    </Group>
  );
}
