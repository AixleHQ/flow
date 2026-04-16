import { Head, usePage } from '@inertiajs/react';

import { ConfigItemsContent, type ConfigItem } from 'shared/resources/config-items/ConfigItemsContent';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Project {
  id: number;
  name: string;
}

interface Props {
  project: Project;
  configItems: ConfigItem[];
}

const ConfigPage = () => {
  const { project, configItems } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <>
      <Head title={`Config — ${project.name}`} />
      <ConfigItemsContent
        configItems={configItems}
        basePath={`/company/projects/${project.id}/config_items`}
        title="Project Config Items"
      />
    </>
  );
};

setPageLayout(ConfigPage, persistentProjectLayout);

export default ConfigPage;
