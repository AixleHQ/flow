import { usePage } from '@inertiajs/react';

import { AuthLayout } from 'layouts/AuthLayout';

import { AssetsContent, type Asset, type AssetVersion, type Folder } from 'shared/resources/assets/AssetsContent';
import { apiV1CompanyAssetsPath, apiV1CompanyFoldersPath } from 'shared/routes';

interface Props {
  assets: Asset[];
  assetVersions?: AssetVersion[];
  folders?: Folder[];
}

const AssetsIndex = () => {
  const { assets, assetVersions, folders } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <AuthLayout>
      <AssetsContent
        assets={assets}
        assetVersions={assetVersions}
        folders={folders}
        title="Company Assets"
        subtitle="Company-wide files and artifacts available across all projects."
        apiBasePath={apiV1CompanyAssetsPath()}
        createEndpoint={apiV1CompanyAssetsPath()}
        foldersApiBase={apiV1CompanyFoldersPath()}
      />
    </AuthLayout>
  );
};

export default AssetsIndex;
