import { Head, usePage } from '@inertiajs/react';

import type { Project } from '@/types/generated';

import type { TrackerOption } from 'shared/resources/triggers/trackerTrigger';
import { TriggersContent } from 'shared/resources/triggers/TriggersContent';
import type { TriggerColumnOption, TriggerWorkflowOption } from 'shared/resources/triggers/types';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Props {
  project: Project;
  workflows: TriggerWorkflowOption[];
  boardColumns: TriggerColumnOption[];
  trackers: TrackerOption[];
  [key: string]: unknown;
}

const TriggersPage = () => {
  const { project, workflows, boardColumns, trackers } = usePage<Props>().props;

  return (
    <>
      <Head title={`Triggers — ${project.name}`} />
      <TriggersContent projectId={project.id} workflows={workflows} columns={boardColumns} trackers={trackers} />
    </>
  );
};

setPageLayout(TriggersPage, persistentProjectLayout);

export default TriggersPage;
