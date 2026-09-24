import { Head, usePage } from '@inertiajs/react';

import type { ConfigItem, Project } from '@/types/generated';

import { ConfigItemsContent } from 'shared/resources/config-items/ConfigItemsContent';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Props {
  project: Project;
  configItems: ConfigItem[];
}

const ConfigPage = () => {
  const { project, configItems } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <>
      <Head title={`Secrets & Variables — ${project.name}`} />
      <ConfigItemsContent
        configItems={configItems}
        basePath={`/company/projects/${project.id}/config_items`}
        title="Secrets & Variables"
      />
    </>
  );
};

setPageLayout(ConfigPage, persistentProjectLayout);

export default ConfigPage;
