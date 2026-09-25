import { Head, usePage } from '@inertiajs/react';

import type { Integration, Project } from '@/types/generated';

import type { AzureDevopsProps } from 'shared/resources/integrations/AzureDevopsConnectModal';
import type { GithubProps } from 'shared/resources/integrations/GithubConnectModal';
import { IntegrationsContent } from 'shared/resources/integrations/IntegrationsContent';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Props {
  project: Project;
  integrations: Integration[];
  azureDevops?: AzureDevopsProps;
  github?: GithubProps;
}

const IntegrationsPage = () => {
  const { project, integrations, azureDevops, github } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <>
      <Head title={`Integrations — ${project.name}`} />
      <IntegrationsContent
        integrations={integrations}
        basePath={`/company/projects/${project.id}/integrations`}
        title="Integrations"
        azureDevops={azureDevops}
        github={github}
      />
    </>
  );
};

setPageLayout(IntegrationsPage, persistentProjectLayout);

export default IntegrationsPage;
