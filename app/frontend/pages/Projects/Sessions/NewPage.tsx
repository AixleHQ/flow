import { Head, usePage } from '@inertiajs/react';
import { Box } from '@mantine/core';

import type { IntegrationPicker, Project, RunnerSummary } from '@/types/generated';

import type { AssetPickerItem } from 'shared/components/AssetPicker';
import { SessionNewForm } from 'shared/components/SessionNewForm';
import type { ConfigItemOption, NamedItem, SessionCostHint } from 'shared/components/SessionNewForm';
import type { ToolGroup } from 'shared/lib/toolPicker';
import { companyProjectSessionPath, companyProjectSessionsPath } from 'shared/routes';
import { PageHeader } from 'shared/ui/PageHeader';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface AgentModel {
  modelId: string;
  displayName: string;
  reasoningEffortLevels: string[];
}

interface AgentModelsEntry {
  agentType: string;
  models: AgentModel[];
  defaultModel?: string | null;
}

interface Props {
  project: Project;
  agentModels?: AgentModelsEntry[];
  agents?: NamedItem[];
  tools?: NamedItem[];
  toolGroups?: ToolGroup[];
  skills?: NamedItem[];
  mcpServers?: NamedItem[];
  repositories?: NamedItem[];
  assets?: AssetPickerItem[];
  configItems?: ConfigItemOption[];
  integrations?: IntegrationPicker[];
  defaultIntegrationIds?: number[];
  costHint?: SessionCostHint;
  runners?: RunnerSummary[];
}

const ProjectSessionNewPage = () => {
  const {
    project,
    agentModels = [],
    agents = [],
    tools = [],
    toolGroups = [],
    skills = [],
    mcpServers = [],
    repositories = [],
    assets = [],
    configItems = [],
    integrations = [],
    defaultIntegrationIds = [],
    costHint,
    runners,
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
          toolGroups={toolGroups}
          skills={skills}
          mcpServers={mcpServers}
          repositories={repositories}
          costHint={costHint}
          assets={assets}
          configItems={configItems}
          integrations={integrations}
          defaultIntegrationIds={defaultIntegrationIds}
          runners={runners}
          onCreatedPath={(sessionId) => companyProjectSessionPath(project.id, sessionId)}
          fallbackPath={companyProjectSessionsPath(project.id)}
        />
      </Box>
    </>
  );
};

setPageLayout(ProjectSessionNewPage, persistentProjectLayout);

export default ProjectSessionNewPage;
