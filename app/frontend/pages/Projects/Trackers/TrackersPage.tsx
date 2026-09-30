import { Head, usePage } from '@inertiajs/react';

import type { Project, ProjectTracker } from '@/types/generated';

import type { AvailableScopeGroup } from 'shared/resources/trackers/AddTrackerDrawer';
import type { IntakeOption } from 'shared/resources/trackers/ConnectColumnDrawer';
import { TrackersContent } from 'shared/resources/trackers/TrackersContent';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Props {
  project: Project;
  trackers: ProjectTracker[];
  availableScopes: AvailableScopeGroup[];
  workflows: IntakeOption[];
  boardColumns: IntakeOption[];
  [key: string]: unknown;
}

const TrackersPage = () => {
  const { project, trackers, availableScopes, workflows, boardColumns } = usePage<Props>().props;

  return (
    <>
      <Head title={`Trackers — ${project.name}`} />
      <TrackersContent
        projectId={project.id}
        trackers={trackers}
        availableScopes={availableScopes}
        workflows={workflows}
        boardColumns={boardColumns}
        basePath={`/company/projects/${project.id}/trackers`}
      />
    </>
  );
};

setPageLayout(TrackersPage, persistentProjectLayout);

export default TrackersPage;
