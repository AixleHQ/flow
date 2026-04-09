import { Head, usePage } from '@inertiajs/react';

import { Integration, IntegrationsContent } from 'shared/resources/integrations/IntegrationsContent';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Project {
  id: number;
  name: string;
}

interface Props {
  project: Project;
  integrations: Integration[];
}

const IntegrationsPage = () => {
  const { project, integrations } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <>
      <Head title={`Integrations — ${project.name}`} />
      <IntegrationsContent
        integrations={integrations}
        basePath={`/company/projects/${project.id}/integrations`}
        title="Integrations"
      />
    </>
  );
};

setPageLayout(IntegrationsPage, persistentProjectLayout);

export default IntegrationsPage;
