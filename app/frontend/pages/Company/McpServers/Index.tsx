import { AuthLayout } from 'layouts/AuthLayout';

import { McpServersContent, type McpServer } from 'shared/resources/mcp-servers/McpServersContent';

interface Props {
  mcpServers: McpServer[];
  configItemNames: string[];
}

function McpServersIndex({ mcpServers, configItemNames }: Props) {
  return (
    <AuthLayout>
      <McpServersContent
        mcpServers={mcpServers}
        configItemNames={configItemNames}
        basePath="/company/mcp_servers"
        title="Company MCP Servers"
        subtitle="Manage company-wide MCP servers. Configure external tools like Context7, Tavily, etc."
      />
    </AuthLayout>
  );
}

export default McpServersIndex;
