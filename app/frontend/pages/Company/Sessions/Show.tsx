import { Head, usePage } from '@inertiajs/react';

import { AuthLayout } from 'layouts/AuthLayout';
import type LlmCall from 'types/generated/LlmCall';
import type TerminalSession from 'types/generated/TerminalSession';

import { SessionShowContent } from 'shared/components/SessionShowContent/SessionShowContent';

interface Props {
  session: TerminalSession;
  llmCalls: LlmCall[];
  cableStream: string;
}

const SessionShowPage = () => {
  const { session, llmCalls, cableStream } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <AuthLayout noPadding>
      <Head title="Session" />
      <SessionShowContent
        session={session}
        llmCalls={llmCalls}
        cableStream={cableStream}
        context={{
          backPath: '/company/sessions',
          backLabel: 'Sessions & Runs',
          // Company-level session creation was removed; omit newSessionPath to hide the "New Session" button.
          artifactsPath: `/company/sessions/${session.id}/artifacts`,
        }}
      />
    </AuthLayout>
  );
};

export default SessionShowPage;
