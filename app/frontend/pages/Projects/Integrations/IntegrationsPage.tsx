import { Head, usePage } from '@inertiajs/react';

import type { AzureDevopsProps } from 'shared/resources/integrations/AzureDevopsConnectModal';
import { Integration, IntegrationsContent } from 'shared/resources/integrations/IntegrationsContent';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Project {
  id: number;
  name: string;
}

interface Props {
  project: Project;
  integrations: Integration[];
  azureDevops?: AzureDevopsProps;
}

const IntegrationsPage = () => {
  const { project, integrations, azureDevops } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <>
      <Head title={`Integrations — ${project.name}`} />
      <IntegrationsContent
        integrations={integrations}
        basePath={`/company/projects/${project.id}/integrations`}
        title="Integrations"
        azureDevops={azureDevops}
      />
    </>
  );
};

setPageLayout(IntegrationsPage, persistentProjectLayout);

export default IntegrationsPage;
