import { Head, usePage } from '@inertiajs/react';

import type LlmCall from 'types/generated/LlmCall';
import type TerminalSession from 'types/generated/TerminalSession';

import {
  SessionShowContent,
  type SessionWorkflowContext,
} from 'shared/components/SessionShowContent/SessionShowContent';

import { persistentProjectLayoutNoPadding, setPageLayout } from '../ProjectLayout';

interface Props {
  project: { id: number; name: string };
  session: TerminalSession;
  workflowContext: SessionWorkflowContext | null;
  llmCalls: LlmCall[];
  cableStream: string;
}

const ProjectSessionShowPage = () => {
  const { project, session, workflowContext, llmCalls, cableStream } = usePage<{ props: Props }>()
    .props as unknown as Props;
  const basePath = `/company/projects/${project.id}/sessions`;

  return (
    <>
      <Head title={`Session #${session.id} — ${project.name}`} />
      <SessionShowContent
        session={session}
        llmCalls={llmCalls}
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
