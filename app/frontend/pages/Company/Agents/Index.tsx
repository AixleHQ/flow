import { AuthLayout } from 'layouts/AuthLayout';

import { AgentsContent, type Agent } from 'shared/resources/agents/AgentsContent';

interface Props {
  agents: Agent[];
}

function AgentsIndex({ agents }: Props) {
  return (
    <AuthLayout>
      <AgentsContent
        agents={agents}
        basePath="/company/agents"
        title="Company Agents"
        subtitle="Manage company-wide agent configurations. These are available in all projects."
      />
    </AuthLayout>
  );
}

export default AgentsIndex;
