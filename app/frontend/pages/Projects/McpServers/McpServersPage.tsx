import { Head, usePage } from '@inertiajs/react';

import type { Connector } from 'shared/resources/connectors/types';
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
  connectors: Connector[];
  connectorQuery: string;
  catalogSyncedAt: string | null;
}

const McpServersPage = () => {
  const { project, mcpServers, configItemNames, connectors, connectorQuery, catalogSyncedAt } = usePage<{
    props: Props;
  }>().props as unknown as Props;

  return (
    <>
      <Head title={`Connectors — ${project.name}`} />
      <McpServersContent
        mcpServers={mcpServers}
        configItemNames={configItemNames}
        basePath={`/company/projects/${project.id}/mcp_servers`}
        title="Connectors"
        subtitle="MCP servers this project can use — installed from the public catalog or added by hand."
        connectors={connectors}
        connectorQuery={connectorQuery}
        connectorsPath={`/company/projects/${project.id}/connectors`}
        catalogSyncedAt={catalogSyncedAt}
      />
    </>
  );
};

setPageLayout(McpServersPage, persistentProjectLayout);

export default McpServersPage;
