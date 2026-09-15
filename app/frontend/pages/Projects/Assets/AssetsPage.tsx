import { Head, usePage } from '@inertiajs/react';

import { AssetsContent, type Asset, type AssetVersion, type Folder } from 'shared/resources/assets/AssetsContent';
import { apiV1ProjectAssetsPath, apiV1ProjectFoldersPath } from 'shared/routes';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface Project {
  id: number;
  name: string;
}

interface Props {
  project: Project;
  assets: Asset[];
  assetVersions?: AssetVersion[];
  folders?: Folder[];
}

const AssetsPage = () => {
  const { project, assets, assetVersions, folders } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <>
      <Head title={`Assets — ${project.name}`} />
      <AssetsContent
        assets={assets}
        assetVersions={assetVersions}
        folders={folders}
        title="Project Assets"
        subtitle="Files and artifacts for this project. Company assets are also accessible."
        isProjectContext
        projectId={project.id}
        apiBasePath={apiV1ProjectAssetsPath(project.id)}
        createEndpoint={apiV1ProjectAssetsPath(project.id)}
        foldersApiBase={apiV1ProjectFoldersPath(project.id)}
      />
    </>
  );
};

setPageLayout(AssetsPage, persistentProjectLayout);

export default AssetsPage;
