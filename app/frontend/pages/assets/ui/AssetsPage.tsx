import { AssetPreview } from 'features/asset-preview';
import { AssetsPanel } from 'features/assets-management';

const AssetsPage = () => (
  <AssetsPanel renderPreview={(data, onClose) => <AssetPreview asset={data} onClose={onClose} />} />
);

export default AssetsPage;
