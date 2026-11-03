import { Head, usePage } from '@inertiajs/react';
import { useEffect } from 'react';

import type TerminalSession from 'types/generated/TerminalSession';

import {
  SessionShowContent,
  type SessionWorkflowContext,
} from 'shared/components/SessionShowContent/SessionShowContent';
import { analytics } from 'shared/lib/analytics';

import { persistentProjectLayoutNoPadding, setPageLayout } from '../ProjectLayout';

interface Props {
  project: { id: number; name: string };
  session: TerminalSession;
  workflowContext: SessionWorkflowContext | null;
  cableStream: string;
}

const ProjectSessionShowPage = () => {
  const { project, session, workflowContext, cableStream } = usePage<{ props: Props }>().props as unknown as Props;
  const sessionId = session.id;
  useEffect(() => {
    analytics.track('session_opened', { session_state: session.state });
    // Once per session opened, not per state change while watching it.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sessionId]);
  const basePath = `/company/projects/${project.id}/sessions`;

  return (
    <>
      <Head title={`Session #${session.id} — ${project.name}`} />
      <SessionShowContent
        session={session}
        cableStream={cableStream}
        workflowContext={workflowContext}
        context={{
          backPath: basePath,
          newSessionPath: `${basePath}/new`,
          artifactsPath: `${basePath}/${session.id}/artifacts`,
        }}
      />
    </>
  );
};

setPageLayout(ProjectSessionShowPage, persistentProjectLayoutNoPadding);

export default ProjectSessionShowPage;
