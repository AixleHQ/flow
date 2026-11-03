import { Head, router } from '@inertiajs/react';
import { Alert, Anchor, Button, Checkbox, Paper, Stack, Text, Title } from '@mantine/core';
import { useState } from 'react';

import { legalAcceptancePath, legalPrivacyPolicyPath, logoutPath } from 'shared/routes';
import { Logo, PageShell } from 'shared/ui';

export interface PendingDocument {
  key: string;
  title: string;
  /** The version this page shows; the server refuses an acceptance of any other. */
  version: string;
  updatedOn: string;
  /** `company` documents are accepted on the company's behalf, `user` ones for yourself. */
  acceptedBy: 'company' | 'user';
  url: string;
}

interface PageProps {
  companyName: string;
  documents: PendingDocument[];
  errors?: { base?: string | string[] };
  [key: string]: unknown;
}

const formatDate = (iso: string) =>
  new Date(`${iso}T00:00:00Z`).toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    timeZone: 'UTC',
  });

function DocumentLink({ document }: { document: PendingDocument }) {
  return (
    <Anchor href={document.url} target="_blank" rel="noopener noreferrer" inherit>
      {document.title}
    </Anchor>
  );
}

function Statement({ document, companyName }: { document: PendingDocument; companyName: string }) {
  if (document.acceptedBy === 'company')
    return (
      <>
        I am authorized to bind {companyName}, and I accept the <DocumentLink document={document} /> on its behalf.
      </>
    );

  return (
    <>
      I am at least 18, {companyName} has authorized me to use Aixle Flow, and I accept the{' '}
      <DocumentLink document={document} />.
    </>
  );
}

// Keyed by version too: a box ticked for text that has since changed is not ticked for the new text.
const tickKey = (document: PendingDocument) => `${document.key}@${document.version}`;

export default function AcceptPage({ companyName, documents, errors = {} }: PageProps) {
  const [checked, setChecked] = useState<Record<string, boolean>>({});
  const [processing, setProcessing] = useState(false);
  const allChecked = documents.every((document) => checked[tickKey(document)]);
  const refusal = [errors.base].flat().filter(Boolean).join(' ');
  const updated = documents.length === 1 ? 'This document has' : 'These documents have';

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    setProcessing(true);
    const accepted = Object.fromEntries(documents.map((document) => [document.key, document.version]));
    router.post(legalAcceptancePath(), { accepted }, { onFinish: () => setProcessing(false) });
  };

  return (
    <PageShell variant="centered">
      <Head title="Review our terms" />
      <Paper p="xl" radius="md" w="100%" maw={480}>
        <form onSubmit={submit}>
          <Stack gap="md">
            <Logo />
            <Title order={3}>Review our terms</Title>
            <Text size="sm" c="dimmed">
              {updated} to be accepted before you continue to {companyName}. Each opens in a new tab.
            </Text>

            {refusal && <Alert color="red">{refusal}</Alert>}

            <Stack gap="sm">
              {documents.map((document) => (
                <Checkbox
                  key={tickKey(document)}
                  checked={Boolean(checked[tickKey(document)])}
                  onChange={(event) => {
                    const { checked: ticked } = event.currentTarget;
                    setChecked((was) => ({ ...was, [tickKey(document)]: ticked }));
                  }}
                  label={<Statement document={document} companyName={companyName} />}
                  description={`Last updated ${formatDate(document.updatedOn)}`}
                />
              ))}
            </Stack>

            <Button type="submit" fullWidth disabled={!allChecked} loading={processing}>
              Accept and continue
            </Button>

            <Text size="xs" c="dimmed">
              How we handle your information is described in our{' '}
              <Anchor size="xs" href={legalPrivacyPolicyPath()} target="_blank" rel="noopener noreferrer">
                Privacy Policy
              </Anchor>
              .
            </Text>
            <Button variant="subtle" color="gray" size="xs" onClick={() => router.delete(logoutPath())}>
              Sign out
            </Button>
          </Stack>
        </form>
      </Paper>
    </PageShell>
  );
}
