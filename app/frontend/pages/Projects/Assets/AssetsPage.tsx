import { Head, usePage } from '@inertiajs/react';

import { apiV1ProjectAssetsPath } from 'shared/routes';
import { AssetsContent, type Asset, type AssetVersion } from 'shared/resources/assets/AssetsContent';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Project {
  id: number;
  name: string;
}

interface Props {
  project: Project;
  assets: Asset[];
  assetVersions?: AssetVersion[];
}

const AssetsPage = () => {
  const { project, assets, assetVersions } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <>
      <Head title={`Assets — ${project.name}`} />
      <AssetsContent
        assets={assets}
        assetVersions={assetVersions}
        title="Project Assets"
        subtitle="Files and artifacts for this project. Company assets are also accessible."
        isProjectContext
        projectId={project.id}
        apiBasePath={apiV1ProjectAssetsPath(project.id)}
        createEndpoint={apiV1ProjectAssetsPath(project.id)}
      />
    </>
  );
};

setPageLayout(AssetsPage, persistentProjectLayout);

export default AssetsPage;
