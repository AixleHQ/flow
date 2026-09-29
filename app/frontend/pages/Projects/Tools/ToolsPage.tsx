import { Head, usePage } from '@inertiajs/react';

import type { Project, Tool } from '@/types/generated';

import { ToolsContent } from 'shared/resources/tools/ToolsContent';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Props {
  project: Project;
  tools: Tool[];
  archivedTools: Tool[];
  configItemNames: string[];
}

const ToolsPage = () => {
  const { project, tools, archivedTools, configItemNames } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <>
      <Head title={`Wrappers — ${project.name}`} />
      <ToolsContent
        tools={tools}
        archivedTools={archivedTools}
        projectId={project.id}
        configItemNames={configItemNames}
        basePath={`/company/projects/${project.id}/tools`}
        title="Wrappers"
        subtitle="No MCP server for a service you use? Write a wrapper for it — any language, any runtime — and agents get it as a tool."
        editableScopeIndicator="project"
      />
    </>
  );
};

setPageLayout(ToolsPage, persistentProjectLayout);

export default ToolsPage;
