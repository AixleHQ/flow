import { Center, Drawer, Loader } from '@mantine/core';

import { SessionNewForm } from 'shared/components/SessionNewForm';

import { useCreateOptions } from './useCreateOptions';

interface Props {
  projectId: number;
  opened: boolean;
  onClose: () => void;
}

/**
 * New Session as a 460px right drawer, so starting a session no longer means
 * leaving the list you started from. The full page at /sessions/new still
 * exists for deep links and renders the same form.
 */
export function NewSessionDrawer({ projectId, opened, onClose }: Props) {
  const options = useCreateOptions(opened);

  return (
    <Drawer
      opened={opened}
      onClose={onClose}
      position="right"
      size={460}
      title="New session"
      padding={0}
      styles={{ body: { padding: 0, height: 'calc(100% - 60px)' } }}
    >
      {options ? (
        <SessionNewForm
          layout="drawer"
          projectId={projectId}
          agentModels={options.agentModels}
          agents={options.agents}
          tools={options.tools}
          skills={options.skills}
          mcpServers={options.mcpServers}
          repositories={options.repositories}
          assets={options.assets}
          costHint={options.costHint}
          onCreatedPath={(sessionId, id) => `/company/projects/${id}/sessions/${sessionId}`}
          fallbackPath={`/company/projects/${projectId}/sessions`}
        />
      ) : (
        <Center h={200}>
          <Loader size="sm" />
        </Center>
      )}
    </Drawer>
  );
}
