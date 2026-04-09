import { Head, usePage } from '@inertiajs/react';

import { McpServersContent, type McpServer } from 'shared/resources/mcp-servers/McpServersContent';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Project {
  id: number;
  name: string;
}

interface Props {
  project: Project;
  mcpServers: McpServer[];
  configItemNames: string[];
}

const McpServersPage = () => {
  const { project, mcpServers, configItemNames } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <>
      <Head title={`MCP Servers — ${project.name}`} />
      <McpServersContent
        mcpServers={mcpServers}
        configItemNames={configItemNames}
        basePath={`/company/projects/${project.id}/mcp_servers`}
        title="Project MCP Servers"
        subtitle="Manage project-specific MCP servers."
      />
    </>
  );
};

setPageLayout(McpServersPage, persistentProjectLayout);

export default McpServersPage;
