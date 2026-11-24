import { Head, usePage } from '@inertiajs/react';

import type TerminalSession from 'types/generated/TerminalSession';

import {
  SessionShowContent,
  type SessionWorkflowContext,
} from 'shared/components/SessionShowContent/SessionShowContent';
import {
  companyProjectSessionArtifactsPath,
  companyProjectSessionsPath,
  newCompanyProjectSessionPath,
} from 'shared/routes';

import { persistentProjectLayoutNoPadding, setPageLayout } from '../ProjectLayout';

interface Props {
  project: { id: number; name: string };
  session: TerminalSession;
  workflowContext: SessionWorkflowContext | null;
  cableStream: string;
}

const ProjectSessionShowPage = () => {
  const { project, session, workflowContext, cableStream } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <>
      <Head title={`Session #${session.id} — ${project.name}`} />
      <SessionShowContent
        session={session}
        cableStream={cableStream}
        workflowContext={workflowContext}
        context={{
          backPath: companyProjectSessionsPath(project.id),
          newSessionPath: newCompanyProjectSessionPath(project.id),
          artifactsPath: companyProjectSessionArtifactsPath(project.id, session.id),
        }}
      />
    </>
  );
};

setPageLayout(ProjectSessionShowPage, persistentProjectLayoutNoPadding);

export default ProjectSessionShowPage;
