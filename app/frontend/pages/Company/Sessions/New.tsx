import { router, usePage } from '@inertiajs/react';
import { Box, Button, Group, Text } from '@mantine/core';
import { IconChevronLeft } from '@tabler/icons-react';

import { AuthLayout } from 'layouts/AuthLayout';

import { SessionNewForm } from 'shared/components/SessionNewForm';
import type { NamedItem } from 'shared/components/SessionNewForm';

interface AgentModel {
  modelId: string;
  displayName: string;
}

interface AgentModelsEntry {
  agentType: string;
  models: AgentModel[];
}

interface Props {
  projects: NamedItem[];
  preSelectedProjectId: number | null;
  agentModels?: AgentModelsEntry[];
  agents?: NamedItem[];
  tools?: NamedItem[];
  skills?: NamedItem[];
  mcpServers?: NamedItem[];
  repositories?: NamedItem[];
  assets?: NamedItem[];
}

const CompanySessionNewPage = () => {
  const {
    projects,
    preSelectedProjectId,
    agentModels = [],
    agents = [],
    tools = [],
    skills = [],
    mcpServers = [],
    repositories = [],
    assets = [],
  } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <AuthLayout>
      <Box maw={720} mx="auto">
        <Group mb="lg">
          <Button
            variant="subtle"
            size="sm"
            leftSection={<IconChevronLeft size={16} />}
            onClick={() => router.visit('/company/sessions')}
          >
            Back
          </Button>
          <Text size="xl" fw={600}>
            New Session
          </Text>
        </Group>

        <SessionNewForm
          projects={projects}
          agentModels={agentModels}
          agents={agents}
          tools={tools}
          skills={skills}
          mcpServers={mcpServers}
          repositories={repositories}
          assets={assets}
          preSelectedProjectId={preSelectedProjectId}
          onCreatedPath={(sessionId) => `/company/sessions/${sessionId}`}
          fallbackPath="/company/sessions"
        />
      </Box>
    </AuthLayout>
  );
};

export default CompanySessionNewPage;
