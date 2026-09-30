import { Center, Loader } from '@mantine/core';

import { RunWorkflowDrawer as RunWorkflowDrawerForm } from 'shared/components/RunWorkflowDrawer';
import { ResourceDrawer } from 'shared/ui/ResourceDrawer';

import { useCreateOptions } from './useCreateOptions';

interface Props {
  projectId: number;
  opened: boolean;
  onClose: () => void;
}

/**
 * Feeds the shared Run Workflow drawer from the list page's optional props.
 * Until they arrive the drawer is a spinner rather than an empty picker.
 */
export function RunWorkflowDrawer({ projectId, opened, onClose }: Props) {
  const options = useCreateOptions(opened);

  if (!options) {
    return (
      <ResourceDrawer opened={opened} onClose={onClose} title="Run workflow">
        <Center h={200}>
          <Loader size="sm" />
        </Center>
      </ResourceDrawer>
    );
  }

  return (
    <RunWorkflowDrawerForm
      opened={opened}
      onClose={onClose}
      projectId={projectId}
      workflows={options.workflows}
      configuredAgents={options.configuredAgents}
      defaultAgentRuntime={options.defaultAgentRuntime}
      agentModels={options.agentModels}
      repositories={options.repositories}
      assets={options.assets}
    />
  );
}
