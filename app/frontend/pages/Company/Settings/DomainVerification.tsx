import { router } from '@inertiajs/react';
import { Alert, Box, Button, Code, Group, Stack, Text } from '@mantine/core';
import { IconCircleCheck } from '@tabler/icons-react';
import { useState } from 'react';

import { companyDomainVerificationPath } from 'shared/routes';

interface Props {
  joining: {
    emailDomain: string | null;
    domainVerifiedAt: string | null;
    verificationHost: string;
    verificationRecord: string;
  };
  isAdmin: boolean;
}

/**
 * Proving the domain, which is what domain auto-join rests on.
 *
 * Signing up proved a mailbox at the domain — that somebody receives mail there.
 * Letting every later arrival from it into the workspace is a claim on the
 * domain itself, and only its owner can publish a DNS record.
 */
export function DomainVerification({ joining, isAdmin }: Props) {
  const [checking, setChecking] = useState(false);
  if (!joining.emailDomain) return null;

  if (joining.domainVerifiedAt) {
    return (
      <Group gap={6} c="var(--app-success-fg)">
        <IconCircleCheck size={16} />
        <Text fz="sm">Domain verified — people signing in from it can join without an invitation.</Text>
      </Group>
    );
  }

  const check = () => {
    setChecking(true);
    router.post(companyDomainVerificationPath(), {}, { preserveScroll: true, onFinish: () => setChecking(false) });
  };

  return (
    <Alert color="yellow" variant="light" title="Verify this domain to let people join automatically">
      <Stack gap="sm">
        <Text fz="sm">
          Publish this TXT record in the DNS for {joining.emailDomain}. Until it is there, everyone joins by invitation.
        </Text>
        <Box>
          <Text fz="xs" fw={500}>
            Name
          </Text>
          <Code block>{joining.verificationHost}</Code>
        </Box>
        <Box>
          <Text fz="xs" fw={500}>
            Value
          </Text>
          <Code block>{joining.verificationRecord}</Code>
        </Box>
        {isAdmin && (
          <Button size="xs" variant="default" loading={checking} onClick={check} style={{ alignSelf: 'flex-start' }}>
            Check now
          </Button>
        )}
      </Stack>
    </Alert>
  );
}
