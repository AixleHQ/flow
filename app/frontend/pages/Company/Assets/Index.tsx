import { usePage } from '@inertiajs/react';

import { AuthLayout } from 'layouts/AuthLayout';

import { AssetsContent, type Asset, type AssetVersion } from 'shared/resources/assets/AssetsContent';
import { apiV1CompanyAssetsPath } from 'shared/routes';

interface Props {
  assets: Asset[];
  assetVersions?: AssetVersion[];
}

const AssetsIndex = () => {
  const { assets, assetVersions } = usePage<{ props: Props }>().props as unknown as Props;

  return (
    <AuthLayout>
      <AssetsContent
        assets={assets}
        assetVersions={assetVersions}
        title="Company Assets"
        subtitle="Company-wide files and artifacts available across all projects."
        apiBasePath={apiV1CompanyAssetsPath()}
        createEndpoint={apiV1CompanyAssetsPath()}
      />
    </AuthLayout>
  );
};

export default AssetsIndex;
