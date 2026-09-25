import { Head, usePage } from '@inertiajs/react';

import type { Agent, Project } from '@/types/generated';

import { AgentsContent } from 'shared/resources/agents/AgentsContent';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Props {
  project: Project;
  agents: Agent[];
}

const AgentsPage = () => {
  const { project, agents } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <>
      <Head title={`Agents — ${project.name}`} />
      <AgentsContent
        agents={agents}
        basePath={`/company/projects/${project.id}/agents`}
        title="Project Agents"
        subtitle="Manage project-specific agent configurations."
      />
    </>
  );
};

setPageLayout(AgentsPage, persistentProjectLayout);

export default AgentsPage;
