import { Head, usePage } from '@inertiajs/react';

import { ToolsContent, type Tool } from 'shared/resources/tools/ToolsContent';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Project {
  id: number;
  name: string;
}

interface Props {
  project: Project;
  tools: Tool[];
  configItemNames: string[];
}

const ToolsPage = () => {
  const { project, tools, configItemNames } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <>
      <Head title={`Tools — ${project.name}`} />
      <ToolsContent
        tools={tools}
        configItemNames={configItemNames}
        basePath={`/company/projects/${project.id}/tools`}
        title="Project Tools"
        subtitle="Manage project-specific tools."
        editableScopeIndicator="project"
      />
    </>
  );
};

setPageLayout(ToolsPage, persistentProjectLayout);

export default ToolsPage;
