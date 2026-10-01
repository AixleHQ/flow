import { Center, Loader } from '@mantine/core';
import { useState } from 'react';

import { SessionNewForm } from 'shared/components/SessionNewForm';
import { useConfirmClose } from 'shared/lib/hooks/useConfirmClose';
import { ResourceDrawer } from 'shared/ui/ResourceDrawer';

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
  const [dirty, setDirty] = useState(false);
  const requestClose = useConfirmClose(dirty, onClose);

  return (
    <ResourceDrawer opened={opened} onClose={requestClose} title="New session" bare>
      {options ? (
        <SessionNewForm
          layout="drawer"
          onDirtyChange={setDirty}
          projectId={projectId}
          agentModels={options.agentModels}
          agents={options.agents}
          tools={options.tools}
          toolGroups={options.toolGroups}
          skills={options.skills}
          mcpServers={options.mcpServers}
          repositories={options.repositories}
          assets={options.assets}
          configItems={options.configItems}
          costHint={options.costHint}
          onCreatedPath={(sessionId, id) => `/company/projects/${id}/sessions/${sessionId}`}
          fallbackPath={`/company/projects/${projectId}/sessions`}
        />
      ) : (
        <Center h={200}>
          <Loader size="sm" />
        </Center>
      )}
    </ResourceDrawer>
  );
}
