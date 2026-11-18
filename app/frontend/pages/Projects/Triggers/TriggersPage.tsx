import { Head, usePage } from '@inertiajs/react';

import type { Project } from '@/types/generated';

import type { TrackerOption } from 'shared/resources/triggers/trackerTrigger';
import { TriggersContent } from 'shared/resources/triggers/TriggersContent';
import type {
  ChatProviderOption,
  TriggerColumnOption,
  TriggerRepository,
  TriggerWorkflowOption,
} from 'shared/resources/triggers/types';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Props {
  project: Project;
  workflows: TriggerWorkflowOption[];
  boardColumns: TriggerColumnOption[];
  trackers: TrackerOption[];
  triggerRepositories?: TriggerRepository[];
  chatProviders?: ChatProviderOption[];
  [key: string]: unknown;
}

const TriggersPage = () => {
  const { project, workflows, boardColumns, trackers, triggerRepositories, chatProviders } = usePage<Props>().props;

  return (
    <>
      <Head title={`Triggers — ${project.name}`} />
      <TriggersContent
        projectId={project.id}
        workflows={workflows}
        columns={boardColumns}
        trackers={trackers}
        repositories={triggerRepositories ?? []}
        chatProviders={chatProviders ?? []}
      />
    </>
  );
};

setPageLayout(TriggersPage, persistentProjectLayout);

export default TriggersPage;
