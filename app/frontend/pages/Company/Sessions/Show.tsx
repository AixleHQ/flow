import { usePage } from '@inertiajs/react';

import { AuthLayout } from 'layouts/AuthLayout';
import type TerminalSession from 'types/generated/TerminalSession';

import { SessionShowContent } from 'shared/components/SessionShowContent/SessionShowContent';

interface Props {
  session: TerminalSession;
  cableStream: string;
}

const SessionShowPage = () => {
  const { session, cableStream } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <AuthLayout noPadding>
      <SessionShowContent
        session={session}
        cableStream={cableStream}
        context={{
          backPath: '/company/sessions',
          newSessionPath: '/company/sessions/new',
          artifactsPath: `/company/sessions/${session.id}/artifacts`,
        }}
      />
    </AuthLayout>
  );
};

export default SessionShowPage;
