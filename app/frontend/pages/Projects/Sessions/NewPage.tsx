import { Head, usePage } from '@inertiajs/react';
import { Box } from '@mantine/core';

import { SessionNewForm } from 'shared/components/SessionNewForm';
import type { ConfigItemOption, NamedItem, SessionCostHint } from 'shared/components/SessionNewForm';
import { PageHeader } from 'shared/ui/PageHeader';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Project {
  id: number;
  name: string;
}

interface AgentModel {
  modelId: string;
  displayName: string;
}

interface AgentModelsEntry {
  agentType: string;
  models: AgentModel[];
}

interface Props {
  project: Project;
  agentModels?: AgentModelsEntry[];
  agents?: NamedItem[];
  tools?: NamedItem[];
  skills?: NamedItem[];
  mcpServers?: NamedItem[];
  repositories?: NamedItem[];
  assets?: NamedItem[];
  configItems?: ConfigItemOption[];
  costHint?: SessionCostHint;
}

const ProjectSessionNewPage = () => {
  const {
    project,
    agentModels = [],
    agents = [],
    tools = [],
    skills = [],
    mcpServers = [],
    repositories = [],
    assets = [],
    configItems = [],
    costHint,
  } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <>
      <Head title={`New Session — ${project.name}`} />
      <Box maw={720} mx="auto">
        <PageHeader title="New Session" subtitle="Pick a runtime and what the agent can reach, then start it." />
        <SessionNewForm
          projectId={project.id}
          agentModels={agentModels}
          agents={agents}
          tools={tools}
          skills={skills}
          mcpServers={mcpServers}
          repositories={repositories}
          costHint={costHint}
          assets={assets}
          configItems={configItems}
          onCreatedPath={(sessionId) => `/company/projects/${project.id}/sessions/${sessionId}`}
          fallbackPath={`/company/projects/${project.id}/sessions`}
        />
      </Box>
    </>
  );
};

setPageLayout(ProjectSessionNewPage, persistentProjectLayout);

export default ProjectSessionNewPage;
