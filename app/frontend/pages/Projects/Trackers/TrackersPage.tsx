import { Head, usePage } from '@inertiajs/react';

import type { Project, ProjectTracker } from '@/types/generated';

import type { AvailableScopeGroup } from 'shared/resources/trackers/AddTrackerDrawer';
import { TrackersContent } from 'shared/resources/trackers/TrackersContent';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Props {
  project: Project;
  trackers: ProjectTracker[];
  availableScopes: AvailableScopeGroup[];
  [key: string]: unknown;
}

const TrackersPage = () => {
  const { project, trackers, availableScopes } = usePage<Props>().props;

  return (
    <>
      <Head title={`Trackers — ${project.name}`} />
      <TrackersContent
        trackers={trackers}
        availableScopes={availableScopes}
        basePath={`/company/projects/${project.id}/trackers`}
      />
    </>
  );
};

setPageLayout(TrackersPage, persistentProjectLayout);

export default TrackersPage;
