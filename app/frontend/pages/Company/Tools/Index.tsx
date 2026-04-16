import { AuthLayout } from 'layouts/AuthLayout';

import { ToolsContent, type Tool } from 'shared/resources/tools/ToolsContent';

interface Props {
  tools: Tool[];
  configItemNames: string[];
}

function ToolsIndex({ tools, configItemNames }: Props) {
  return (
    <AuthLayout>
      <ToolsContent
        tools={tools}
        configItemNames={configItemNames}
        basePath="/company/tools"
        title="Company Tools"
        subtitle="Manage company-wide tools. System tools are platform-provided and read-only."
      />
    </AuthLayout>
  );
}

export default ToolsIndex;
